import AVFoundation

enum FlashCycle {
    static func next(current: AVCaptureDevice.FlashMode, supported: [AVCaptureDevice.FlashMode]) -> AVCaptureDevice.FlashMode {
        let modes: [AVCaptureDevice.FlashMode] = [.off, .on, .auto]
        let available = modes.filter { supported.contains($0) }
        guard !available.isEmpty else { return .off }
        guard let index = available.firstIndex(of: current) else { return available[0] }
        return available[(index + 1) % available.count]
    }
}
