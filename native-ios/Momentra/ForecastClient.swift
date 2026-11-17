import Foundation
import CoreLocation

struct ForecastCacheRecord: Codable {
    let requestedAt: Date
    let retryAt: Date
    let lastModified: String?
    let responseBody: Data?

    func mayRequest(at now: Date) -> Bool { now >= requestedAt && now >= retryAt }
}

enum ForecastCachePolicy {
    static func httpDate(_ text: String?) -> Date? {
        guard let text, text.count < 128, !text.contains("\n"), !text.contains("\r") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        return formatter.date(from: text)
    }

    static func retryDate(now: Date, expires: String?, retryAfter: String?, status: Int) -> Date {
        var result = now.addingTimeInterval(status == 429 || status == 503 ? 86400 : 10800)
        if let expiry = httpDate(expires), expiry > result { result = expiry }
        if let retryAfter {
            if let seconds = Double(retryAfter), seconds.isFinite, seconds >= 0 {
                result = seconds > 3_153_600_000 ? .distantFuture : max(result, now.addingTimeInterval(seconds))
            } else if let date = httpDate(retryAfter) { result = max(result, date) }
        }
        return result
    }
}

struct ForecastCacheStore {
    let root: URL

    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Forecast", isDirectory: true)
    }

    private func path(for key: String) throws -> URL {
        guard key.count <= 32, key.allSatisfy({ "0123456789-.,".contains($0) }) else { throw ForecastError.invalid }
        return root.appendingPathComponent(key + ".json")
    }

    func read(_ key: String) throws -> ForecastCacheRecord? {
        let url = try path(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_500_000 else { throw ForecastError.invalid }
        let record = try JSONDecoder().decode(ForecastCacheRecord.self, from: data)
        guard record.requestedAt.timeIntervalSince1970.isFinite, record.retryAt.timeIntervalSince1970.isFinite,
              record.retryAt.timeIntervalSince(record.requestedAt) >= 10800 else { throw ForecastError.invalid }
        return record
    }

    func write(_ record: ForecastCacheRecord, key: String) throws {
        let url = try path(for: key)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try JSONEncoder().encode(record).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

enum ForecastError: LocalizedError {
    case invalid, consent, location, cooldown, unavailable, inactive
    var errorDescription: String? {
        switch self {
        case .invalid: return "Dados meteorológicos inválidos."
        case .consent: return "É necessário ler e aceitar os termos da MET Norway."
        case .location: return "Localização recente indisponível para a consulta."
        case .cooldown: return "Aguarde o próximo horário permitido para atualizar a previsão."
        case .unavailable: return "Previsão indisponível; a câmera continua funcionando."
        case .inactive: return "A consulta foi interrompida porque o app não está ativo."
        }
    }
}

private final class ForecastRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https", request.url?.host == "api.met.no" else { completionHandler(nil); return }
        var next = request
        next.setValue("Momentra/0.1 github.com/Sagittaryuz/momentra", forHTTPHeaderField: "User-Agent")
        completionHandler(next)
    }
}

enum ForecastClient {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    static func transport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let delegate = ForecastRedirectDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ForecastError.unavailable }
        return (data, response)
    }

    @MainActor
    static func fetch(location: CLLocation, now: Date, consent: Bool, isForeground: @escaping () -> Bool, store: ForecastCacheStore, transport: Transport) async throws -> Forecast {
        guard consent else { throw ForecastError.consent }
        guard isForeground(), !Task.isCancelled else { throw ForecastError.inactive }
        guard location.horizontalAccuracy >= 0, location.timestamp <= now, now.timeIntervalSince(location.timestamp) <= 60,
              let key = ForecastModel.coordinateKey(location.coordinate) else { throw ForecastError.location }
        let previous = try store.read(key)
        if let previous, !previous.mayRequest(at: now) {
            guard now >= previous.requestedAt, let data = previous.responseBody, let sample = ForecastModel.parse(data, at: now) else { throw ForecastError.cooldown }
            return sample
        }
        let parts = key.split(separator: ",")
        guard parts.count == 2, let url = URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=\(parts[0])&lon=\(parts[1])") else { throw ForecastError.invalid }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("Momentra/0.1 github.com/Sagittaryuz/momentra", forHTTPHeaderField: "User-Agent")
        if let lastModified = previous?.lastModified, ForecastCachePolicy.httpDate(lastModified) != nil { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        // Persist a conservative lock before the network call so a crash cannot bypass the rate limit.
        try store.write(ForecastCacheRecord(requestedAt: now, retryAt: now.addingTimeInterval(86400), lastModified: previous?.lastModified, responseBody: previous?.responseBody), key: key)
        guard isForeground(), !Task.isCancelled else { throw ForecastError.inactive }
        let (data, response) = try await transport(request)
        let status = response.statusCode
        let retryAt = ForecastCachePolicy.retryDate(now: now, expires: response.value(forHTTPHeaderField: "Expires"), retryAfter: response.value(forHTTPHeaderField: "Retry-After"), status: status)
        // Record server limits even if the response is invalid or the app loses foreground.
        let conservativeRetry = max(now.addingTimeInterval(86400), retryAt)
        try store.write(ForecastCacheRecord(requestedAt: now, retryAt: conservativeRetry, lastModified: previous?.lastModified, responseBody: previous?.responseBody), key: key)
        guard isForeground(), !Task.isCancelled else { throw ForecastError.inactive }
        if status == 429 {
            throw ForecastError.cooldown
        }
        guard status == 200 || status == 304 else { throw ForecastError.unavailable }
        let body = status == 304 ? previous?.responseBody : data
        guard let body, body.count <= 1_000_000, let sample = ForecastModel.parse(body, at: now) else { throw ForecastError.unavailable }
        let modified = response.value(forHTTPHeaderField: "Last-Modified") ?? previous?.lastModified
        try store.write(ForecastCacheRecord(requestedAt: now, retryAt: retryAt, lastModified: modified, responseBody: body), key: key)
        return sample
    }
}
