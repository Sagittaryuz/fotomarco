import Foundation
import CryptoKit
import CoreLocation

struct CaptureProfileTag: Codable, Equatable {
    let id: UUID
    let name: String
}

struct CaptureProfileRecord: Codable {
    let captureID: UUID
    let profile: CaptureProfileTag
    let captureDate: Date?
    var localAssetID: String?
    var cloudMediaIDs: [String]
    var latitude: Double? = nil
    var longitude: Double? = nil
}

struct PhotoProfileLookup {
    var captures: [UUID: CaptureProfileTag] = [:]
    var dates: [UUID: Date] = [:]
    var assets: [String: CaptureProfileTag] = [:]
    var assetCaptures: [String: UUID] = [:]
    var cloud: [String: CaptureProfileTag] = [:]
    var locations: [UUID: CLLocationCoordinate2D] = [:]
}

/// Association metadata is stored separately and never printed into the image.
/// Existing photographs without a record deliberately remain unassigned.
enum PhotoProfileIndex {
    private static let lock = NSLock()

    static func register(captureID: UUID, profile: CaptureProfileTag, captureDate: Date? = nil, root: URL? = nil, location: CLLocation? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        let directory = try indexDirectory(root: root)
        let file = directory.appendingPathComponent(captureID.uuidString + ".json")
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        let safeName = String(profile.name.prefix(60))
        try save(CaptureProfileRecord(captureID: captureID,
                                      profile: CaptureProfileTag(id: profile.id, name: safeName),
                                      captureDate: captureDate, localAssetID: nil, cloudMediaIDs: [],
                                      latitude: location?.coordinate.latitude, longitude: location?.coordinate.longitude), to: file)
    }

    static func bindLocal(captureID: UUID, assetID: String, root: URL? = nil) throws {
        guard !assetID.isEmpty, assetID.utf8.count <= 1024 else { return }
        try update(captureID: captureID, root: root) { $0.localAssetID = assetID }
    }

    static func cloudKey(owner: String, mediaID: String) -> String {
        let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return hash + "|" + mediaID
    }

    static func bindCloud(captureID: UUID, owner: String, mediaID: String, root: URL? = nil) throws {
        guard !owner.isEmpty, owner.utf8.count <= 512, !mediaID.isEmpty, mediaID.utf8.count <= 512 else { return }
        let key = cloudKey(owner: owner, mediaID: mediaID)
        try update(captureID: captureID, root: root) { record in
            if !record.cloudMediaIDs.contains(key) { record.cloudMediaIDs.append(key) }
        }
    }

    static func load(root: URL? = nil) -> PhotoProfileLookup {
        lock.lock(); defer { lock.unlock() }
        guard let directory = try? indexDirectory(root: root),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return PhotoProfileLookup()
        }
        var lookup = PhotoProfileLookup()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), data.count <= 16384,
                  let record = try? JSONDecoder().decode(CaptureProfileRecord.self, from: data),
                  file.deletingPathExtension().lastPathComponent == record.captureID.uuidString else { continue }
            lookup.captures[record.captureID] = record.profile
            if let latitude = record.latitude, let longitude = record.longitude {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                if CLLocationCoordinate2DIsValid(coordinate) { lookup.locations[record.captureID] = coordinate }
            }
            if let date = record.captureDate { lookup.dates[record.captureID] = date }
            if let id = record.localAssetID {
                lookup.assets[id] = record.profile
                lookup.assetCaptures[id] = record.captureID
            }
            for id in record.cloudMediaIDs { lookup.cloud[id] = record.profile }
        }
        return lookup
    }

    private static func update(captureID: UUID, root: URL?, mutate: (inout CaptureProfileRecord) -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        let file = try indexDirectory(root: root).appendingPathComponent(captureID.uuidString + ".json")
        let data = try Data(contentsOf: file)
        guard data.count <= 16384, var value = try? JSONDecoder().decode(CaptureProfileRecord.self, from: data),
              value.captureID == captureID else { throw CocoaError(.fileReadCorruptFile) }
        mutate(&value)
        try save(value, to: file)
    }

    private static func indexDirectory(root: URL?) throws -> URL {
        let base = try root ?? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("CaptureProfiles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory
    }
    private static func save(_ value: CaptureProfileRecord, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

struct GalleryGroup<Item>: Identifiable {
    let date: Date?
    let profile: CaptureProfileTag?
    let items: [Item]
    var showsProfile = true
    var id: String { "\(date?.timeIntervalSince1970 ?? -1)|\(profile?.id.uuidString ?? "none")" }
    var title: String {
        let locale = Locale(identifier: "pt_BR")
        let dateTitle = date.map { $0.formatted(.dateTime.day().month(.wide).year().locale(locale)) } ?? "Sem data"
        if !showsProfile {
            guard let date else { return dateTitle }
            let weekday = date.formatted(.dateTime.weekday(.wide).locale(locale))
            let prefix = Calendar.current.isDateInToday(date) ? "Hoje · " : ""
            return "\(prefix)\(dateTitle) · \(weekday)"
        }
        let profileTitle = profile?.name.isEmpty == false ? profile!.name : "Sem perfil"
        return "\(dateTitle) · \(profileTitle)"
    }
}

enum GalleryGrouping {
    private struct Key: Hashable {
        let date: Date?
        let profileID: UUID?
    }
    static func groups<Item>(_ items: [Item], date: (Item) -> Date?, profile: (Item) -> CaptureProfileTag?) -> [GalleryGroup<Item>] {
        let calendar = Calendar.current
        var values: [Key: (CaptureProfileTag?, [Item])] = [:]
        for item in items {
            let tag = profile(item)
            let key = Key(date: date(item).map { calendar.startOfDay(for: $0) }, profileID: tag?.id)
            if values[key] == nil { values[key] = (tag, []) }
            values[key]?.1.append(item)
        }
        return values.map { key, value in GalleryGroup(date: key.date, profile: value.0, items: value.1) }
            .sorted {
                if $0.date != $1.date { return ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                return ($0.profile?.name ?? "").localizedCaseInsensitiveCompare($1.profile?.name ?? "") == .orderedAscending
            }
    }
}

enum GalleryZoom {
    static let levels = [2, 3, 5, 8]
    static func next(columns: Int, magnification: CGFloat) -> Int {
        let index = levels.firstIndex(of: columns) ?? 1
        if magnification > 1.15 { return levels[max(0, index - 1)] }
        if magnification < 0.85 { return levels[min(levels.count - 1, index + 1)] }
        return levels[index]
    }
}

enum CloudProfileFilename {
    static func encode(captureID: UUID, profile: CaptureProfileTag, originalExtension: String? = nil) -> String {
        var text = String(profile.name.prefix(60))
        while text.utf8.count > 72 { text.removeLast() }
        let name = Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let suffix = originalExtension.map { ".original." + $0.lowercased() } ?? ".jpg"
        return "MTR1.\(profile.id.uuidString).\(name).\(captureID.uuidString)" + suffix
    }

    static func isOriginal(_ filename: String) -> Bool {
        let parts = filename.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 6 && parts[4] == "original" && decode(filename) != nil
    }

    static func decode(_ filename: String) -> CaptureProfileTag? {
        let parts = filename.split(separator: ".", omittingEmptySubsequences: false)
        let processed = parts.count == 5 && parts[4].lowercased() == "jpg"
        let original = parts.count == 6 && parts[4] == "original" && ["jpg", "jpeg", "heic", "heif"].contains(parts[5].lowercased())
        guard (processed || original), parts[0] == "MTR1",
              let id = UUID(uuidString: String(parts[1])), UUID(uuidString: String(parts[3])) != nil,
              parts[2].utf8.count <= 128 else { return nil }
        var encoded = String(parts[2]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let bytes = Data(base64Encoded: encoded), let name = String(data: bytes, encoding: .utf8),
              name.count <= 60 else { return nil }
        return CaptureProfileTag(id: id, name: name)
    }
}
