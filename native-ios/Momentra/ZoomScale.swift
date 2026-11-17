import CoreGraphics

// AVFoundation zoom factors on a virtual device start at its widest lens.
// The UI instead expresses zoom relative to the standard wide camera.
struct ZoomScale {
    let wideFactor: CGFloat
    let minimum: CGFloat
    let maximum: CGFloat

    func deviceFactor(for display: CGFloat) -> CGFloat? {
        guard wideFactor.isFinite, wideFactor > 0, minimum.isFinite, maximum.isFinite,
              minimum >= 1, maximum >= minimum, display.isFinite, display > 0 else { return nil }
        let target = display * wideFactor
        if display == 0.5, abs(minimum / wideFactor - display) < 0.07 { return minimum }
        return target >= minimum && target <= maximum ? target : nil
    }

    var options: [CGFloat] { [CGFloat(0.5), 1, 2, 3].filter { deviceFactor(for: $0) != nil } }
}
