import SwiftUI
import CoreLocation

@MainActor
final class ForecastService: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var status: String?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var forecast: Forecast?
    private var coordinateKey: String?
    private var nextRefresh = Date.distantPast

    func consult(location: CLLocation?, consent: Bool) {
        guard !isLoading else { return }
        guard let location, let key = ForecastModel.coordinateKey(location.coordinate) else {
            status = "Localização recente indisponível para a consulta."
            return
        }
        generation += 1
        let currentGeneration = generation
        isLoading = true
        status = "Consultando previsão…"
        task = Task { @MainActor in
            do {
                let result = try await ForecastClient.fetch(location: location, now: Date(), consent: consent,
                    isForeground: { UIApplication.shared.applicationState == .active },
                    store: try ForecastCacheStore(), transport: ForecastClient.transport)
                guard !Task.isCancelled, generation == currentGeneration else { return }
                forecast = result
                coordinateKey = key
                status = "Previsão disponível para o carimbo."
            } catch {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                status = (error as? LocalizedError)?.errorDescription ?? "Previsão indisponível."
            }
            guard generation == currentGeneration else { return }
            isLoading = false
            task = nil
        }
    }

    func refresh(location: CLLocation?) {
        let now = Date()
        guard !isLoading, now >= nextRefresh, let location, location.horizontalAccuracy >= 0,
              location.timestamp <= now, now.timeIntervalSince(location.timestamp) <= 60,
              current(location: location, at: now) == nil else { return }
        nextRefresh = now.addingTimeInterval(60)
        consult(location: location, consent: true)
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isLoading = false
    }

    func current(location: CLLocation?, at date: Date) -> Forecast? {
        guard let location, location.horizontalAccuracy >= 0, location.timestamp <= date,
              date.timeIntervalSince(location.timestamp) <= 60,
              ForecastModel.coordinateKey(location.coordinate) == coordinateKey,
              let forecast, forecast.isValid(at: date) else { return nil }
        return forecast
    }
}
