import Foundation

enum CaptureMotion {
    static func aspectFit(_ image: CGSize, in bounds: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0, !bounds.isEmpty else { return .zero }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func elapsedSeconds(from start: ContinuousClock.Instant, to now: ContinuousClock.Instant) -> Int64 {
        max(0, start.duration(to: now).components.seconds)
    }

    static func timerLabel(seconds: Int64) -> String {
        let elapsed = max(0, seconds)
        let minutes = (elapsed / 60) % 60
        let remainder = elapsed % 60
        if elapsed >= 3600 {
            return String(format: "%02lld:%02lld:%02lld", elapsed / 3600, minutes, remainder)
        }
        return String(format: "%02lld:%02lld", minutes, remainder)
    }
}
