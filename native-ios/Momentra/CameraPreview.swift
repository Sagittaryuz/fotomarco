import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    let onCaptureRotation: (CGFloat) -> Void
    let focus: (CGPoint, AVCaptureDevice, @escaping (Bool) -> Void) -> Void
    var onTap: () -> Void = {}
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(frame: .zero)
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.update(device: device, onCaptureRotation: onCaptureRotation, focus: focus, onTap: onTap)
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {
        view.previewLayer.session = session
        view.update(device: device, onCaptureRotation: onCaptureRotation, focus: focus, onTap: onTap)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private weak var currentDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewObservation: NSKeyValueObservation?
    private var captureObservation: NSKeyValueObservation?
    private var currentPreviewRotation: CGFloat = 0
    private var onCaptureRotation: ((CGFloat) -> Void)?
    private var focus: ((CGPoint, AVCaptureDevice, @escaping (Bool) -> Void) -> Void)?
    private var onTap: (() -> Void)?
    private let reticle = CAShapeLayer()
    private var lastFocus = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        reticle.bounds = CGRect(x: 0, y: 0, width: 68, height: 68)
        reticle.path = UIBezierPath(roundedRect: reticle.bounds.insetBy(dx: 1, dy: 1), cornerRadius: 4).cgPath
        reticle.strokeColor = UIColor.systemYellow.cgColor
        reticle.fillColor = UIColor.clear.cgColor
        reticle.lineWidth = 1.5
        reticle.opacity = 0
        layer.addSublayer(reticle)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapPreview(_:))))
    }

    required init?(coder: NSCoder) { return nil }

    func update(device: AVCaptureDevice?, onCaptureRotation: @escaping (CGFloat) -> Void,
                focus: @escaping (CGPoint, AVCaptureDevice, @escaping (Bool) -> Void) -> Void,
                onTap: @escaping () -> Void) {
        self.onCaptureRotation = onCaptureRotation
        self.focus = focus
        self.onTap = onTap
        guard currentDevice !== device else { applyPreviewRotation(); return }
        lastFocus = UUID()
        reticle.removeAllAnimations()
        currentDevice = device
        previewObservation = nil
        captureObservation = nil
        rotationCoordinator = nil
        guard let device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        previewObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
            self?.currentPreviewRotation = coordinator.videoRotationAngleForHorizonLevelPreview
            self?.applyPreviewRotation()
        }
        captureObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            self?.onCaptureRotation?(coordinator.videoRotationAngleForHorizonLevelCapture)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPreviewRotation()
    }

    private func applyPreviewRotation() {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(currentPreviewRotation) else { return }
        connection.videoRotationAngle = currentPreviewRotation
    }

    @objc private func tapPreview(_ sender: UITapGestureRecognizer) {
        onTap?()
        let position = sender.location(in: self)
        guard bounds.contains(position), let device = currentDevice, previewLayer.connection?.isActive == true else { return }
        let point = previewLayer.captureDevicePointConverted(fromLayerPoint: position)
        let request = UUID()
        lastFocus = request
        focus?(point, device) { [weak self] accepted in
            guard let self, self.lastFocus == request, accepted, self.bounds.contains(position) else { return }
            self.showFocus(at: position)
        }
    }

    private func showFocus(at point: CGPoint) {
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 1, 0]
        opacity.keyTimes = [0, 0.8, 1]
        opacity.duration = 1.25
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        reticle.position = point
        reticle.add(opacity, forKey: "focusFeedback")
        CATransaction.commit()
    }
}

enum CameraPointFocus {
    static func apply(point: CGPoint, to device: AVCaptureDevice) -> Bool {
        guard point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y),
              device.isFocusPointOfInterestSupported else { return false }
        let mode: AVCaptureDevice.FocusMode = device.isFocusModeSupported(.autoFocus) ? .autoFocus : .continuousAutoFocus
        guard device.isFocusModeSupported(mode), (try? device.lockForConfiguration()) != nil else { return false }
        defer { device.unlockForConfiguration() }
        device.focusPointOfInterest = point
        device.focusMode = mode
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposurePointOfInterest = point
            device.exposureMode = .continuousAutoExposure
        }
        return true
    }
}
