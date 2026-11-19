import CoreMotion
import Foundation

struct PressureSample {
    let hectopascals: Double
    let observedAt: Date

    func isValid(at date: Date) -> Bool {
        hectopascals.isFinite && (300...1200).contains(hectopascals) && observedAt <= date && date.timeIntervalSince(observedAt) <= 10
    }
}

@MainActor
final class PressureService: ObservableObject {
    @Published private(set) var sample: PressureSample?
    @Published private(set) var available = CMAltimeter.isRelativeAltitudeAvailable()
    private let altimeter = CMAltimeter()
    private var generation = 0
    private var tracking = false

    func setEnabled(_ enabled: Bool) {
        let canTrack = enabled && CMAltimeter.isRelativeAltitudeAvailable()
        guard canTrack != tracking else { return }
        tracking = canTrack
        generation += 1
        let current = generation
        altimeter.stopRelativeAltitudeUpdates()
        sample = nil
        available = CMAltimeter.isRelativeAltitudeAvailable()
        guard tracking else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            let uptime = ProcessInfo.processInfo.systemUptime
            let sampleUptime = data?.timestamp
            let pressure = data?.pressure.doubleValue
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                guard error == nil, let sampleUptime, let pressure else { self.sample = nil; return }
                let age = uptime - sampleUptime
                guard age >= 0, age <= 10 else { self.sample = nil; return }
                let sample = PressureSample(hectopascals: pressure * 10, observedAt: Date().addingTimeInterval(-age))
                self.sample = sample.isValid(at: Date()) ? sample : nil
            }
        }
    }
}
