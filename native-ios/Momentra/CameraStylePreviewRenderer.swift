import AVFoundation
import CoreImage
import Metal
import QuartzCore
import UIKit

/// A single in-flight GPU frame prevents camera data from accumulating behind the visor.
final class CameraStylePreviewRenderer {
    private struct Settings {
        var style: MomentraPhotoStyle = .natural
        var adjustments = PhotoStyleAdjustments()
        var active = false
        var targetRotation: CGFloat = 0
        var targetMirrored = false
        var generation = 0
    }
    private let lock = NSLock()
    private let frameQueue = DispatchQueue(label: "br.com.momentra.camera.style-preview", qos: .userInteractive)
    private let inFlight = DispatchSemaphore(value: 1)
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue = device?.makeCommandQueue()
    private lazy var context: CIContext? = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var settings = Settings()
    private weak var layer: CAMetalLayer?

    /// Called only on the main thread by the preview view.
    func attach(_ target: CAMetalLayer) {
        target.device = device
        target.pixelFormat = .bgra8Unorm
        target.framebufferOnly = false
        target.colorspace = colorSpace
        target.isOpaque = true
        target.isHidden = false
        target.opacity = 0
        lock.lock(); layer = target; lock.unlock()
    }

    /// Called on the main thread when the selected style or camera mode changes.
    func configure(style: MomentraPhotoStyle, adjustments: PhotoStyleAdjustments, enabled: Bool) -> Bool {
        let active = enabled && (style.filterName != nil || !adjustments.isNeutral) && device != nil
        lock.lock()
        let changed = settings.active != active
        settings.style = style
        settings.adjustments = adjustments
        settings.active = active
        if changed { settings.generation += 1 }
        let target = layer
        lock.unlock()
        if changed {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            target?.opacity = 0
            CATransaction.commit()
        }
        return active
    }

    /// Matches the rotation and mirroring chosen for AVCaptureVideoPreviewLayer.
    func setPreviewGeometry(rotation: CGFloat, mirrored: Bool) {
        lock.lock(); settings.targetRotation = rotation; settings.targetMirrored = mirrored; lock.unlock()
    }

    func submit(_ pixelBuffer: CVPixelBuffer, rotation: CGFloat, mirrored: Bool) {
        lock.lock(); let state = settings; let target = layer; lock.unlock()
        guard state.active, let target, inFlight.wait(timeout: .now()) == .success else { return }
        frameQueue.async { [weak self, weak target] in
            guard let self, let target, let context = self.context, let queue = self.commandQueue,
                  let drawable = target.nextDrawable(), let command = queue.makeCommandBuffer() else {
                self?.inFlight.signal(); return
            }
            let size = CGSize(width: CGFloat(drawable.texture.width), height: CGFloat(drawable.texture.height))
            guard size.width > 0, size.height > 0 else { self.inFlight.signal(); return }
            let input = CIImage(cvPixelBuffer: pixelBuffer)
            let styled = state.style.apply(to: input, adjustments: state.adjustments)
            let image = Self.fit(styled, to: size, rotation: state.targetRotation - rotation,
                                 mirror: state.targetMirrored != mirrored)
            context.render(image, to: drawable.texture, commandBuffer: command,
                           bounds: CGRect(origin: .zero, size: size), colorSpace: self.colorSpace)
            command.present(drawable)
            command.addCompletedHandler { [weak self, weak target, pixelBuffer] buffer in
                // Keep the camera buffer alive until the GPU has finished reading it.
                _ = pixelBuffer
                guard let self else { return }
                self.inFlight.signal()
                guard buffer.status == .completed else { return }
                DispatchQueue.main.async { [weak self, weak target] in
                    guard let self, let target else { return }
                    self.lock.lock()
                    let show = self.settings.active && self.settings.generation == state.generation && self.layer === target
                    self.lock.unlock()
                    if show {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        target.opacity = 1
                        CATransaction.commit()
                    }
                }
            }
            command.commit()
        }
    }

    static func fit(_ image: CIImage, to size: CGSize, rotation: CGFloat, mirror: Bool) -> CIImage {
        let radians = -rotation * .pi / 180
        var output = image.transformed(by: CGAffineTransform(rotationAngle: radians))
        var extent = output.extent
        output = output.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        extent = output.extent
        if mirror {
            output = output.transformed(by: CGAffineTransform(translationX: extent.width, y: 0).scaledBy(x: -1, y: 1))
        }
        guard extent.width > 0, extent.height > 0 else { return output }
        let scale = max(size.width / extent.width, size.height / extent.height)
        output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        output = output.transformed(by: CGAffineTransform(translationX: (size.width - extent.width * scale) / 2,
                                                         y: (size.height - extent.height * scale) / 2))
        return output.cropped(to: CGRect(origin: .zero, size: size))
    }
}
