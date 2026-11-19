import CoreGraphics
import Foundation

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

    var options: [CGFloat] { [CGFloat(0.5), 1, 2, 4, 8].filter { deviceFactor(for: $0) != nil } }
}

/// Horizontal drag adjusts immediately, then keeps moving at a rate set by the deflection.
struct ContinuousCameraZoom {
    private(set) var value: CGFloat
    private var lastTranslation: CGFloat = 0
    private var deflection: CGFloat = 0

    init(value: CGFloat) { self.value = value }

    mutating func move(to translation: CGFloat, range: ClosedRange<CGFloat>) {
        let delta = translation - lastTranslation
        guard abs(delta) >= 1 else { return }
        lastTranslation = translation
        if (delta > 0) != (deflection > 0) { deflection = 0 }
        deflection = min(80, max(-80, deflection + delta))
        multiply(by: exp(delta / 210), range: range)
    }

    @discardableResult
    mutating func advance(seconds: Double, range: ClosedRange<CGFloat>) -> CGFloat {
        let intensity = max(0, abs(deflection) - 6) / 74
        let direction: CGFloat = deflection < 0 ? -1 : 1
        multiply(by: exp(direction * intensity * intensity * 1.65 * CGFloat(seconds)), range: range)
        return value
    }

    private mutating func multiply(by factor: CGFloat, range: ClosedRange<CGFloat>) {
        value = min(range.upperBound, max(range.lowerBound, value * factor))
    }
}

/// Each pinch scales the current zoom and can reverse immediately at either limit.
struct PreviewPinchZoom {
    private(set) var value: CGFloat
    private var previousMagnification: CGFloat = 1

    init(value: CGFloat) { self.value = value }

    mutating func move(to magnification: CGFloat, range: ClosedRange<CGFloat>) {
        guard magnification.isFinite, magnification > 0 else { return }
        value = min(range.upperBound, max(range.lowerBound, value * (magnification / previousMagnification)))
        previousMagnification = magnification
    }
}

/// Vertical movement while holding the shutter maps smoothly to optical zoom.
enum QuickCaptureZoom {
    static func value(start: CGFloat, verticalTranslation: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        guard start.isFinite, verticalTranslation.isFinite, start > 0 else { return range.lowerBound }
        let factor = start * CGFloat(pow(2.0, Double(-verticalTranslation / 180)))
        return min(range.upperBound, max(range.lowerBound, factor))
    }
}
