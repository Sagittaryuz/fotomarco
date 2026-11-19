import AVFoundation
import SwiftUI

struct CameraPreview: View {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    let onCaptureRotation: (CGFloat) -> Void
    let focus: (CGPoint, AVCaptureDevice, @escaping (Bool) -> Void) -> Void
    var onTap: () -> Void = {}
    var onPinch: ((CGFloat?) -> Void)?
    @GestureState private var pinching = false
    @State private var bridge = CameraPreviewBridge()
    @State private var marker: FocusMarker?
    @State private var focusRequest = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct FocusMarker: Identifiable {
        let id = UUID()
        let point: CGPoint
    }

    var body: some View {
        CameraPreviewLayer(session: session, device: device, onCaptureRotation: onCaptureRotation, bridge: bridge)
            .overlay {
                Rectangle().fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local, perform: tapPreview)
                    .simultaneousGesture(
                        MagnifyGesture(minimumScaleDelta: 0.01)
                            .updating($pinching) { _, active, _ in active = true }
                            .onChanged { onPinch?($0.magnification) },
                        including: onPinch == nil ? .none : .all
                    )
                    .accessibilityHidden(true)
            }
            .overlay {
                if let marker {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(uiColor: .systemYellow), lineWidth: 1.5)
                        .frame(width: 68, height: 68)
                        .position(marker.point)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .task(id: marker?.id) {
                guard let marker else { return }
                do { try await Task.sleep(for: .seconds(1.25)) } catch { return }
                guard self.marker?.id == marker.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { self.marker = nil }
            }
            .onChange(of: pinching) { _, active in
                if !active { onPinch?(nil) }
            }
            .onChange(of: device?.uniqueID) { _, _ in
                focusRequest = UUID()
                marker = nil
            }
    }

    private func tapPreview(at position: CGPoint) {
        onTap()
        guard let device, let point = bridge.view?.captureDevicePoint(at: position) else { return }
        let request = UUID()
        focusRequest = request
        focus(point, device) { accepted in
            guard accepted, focusRequest == request else { return }
            marker = FocusMarker(point: position)
        }
    }
}

private final class CameraPreviewBridge {
    weak var view: PreviewView?
}

private struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    let onCaptureRotation: (CGFloat) -> Void
    let bridge: CameraPreviewBridge

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(frame: .zero)
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.update(device: device, onCaptureRotation: onCaptureRotation)
        bridge.view = view
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
        view.update(device: device, onCaptureRotation: onCaptureRotation)
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
    func update(device: AVCaptureDevice?, onCaptureRotation: @escaping (CGFloat) -> Void) {
        self.onCaptureRotation = onCaptureRotation
        guard currentDevice !== device else { applyPreviewRotation(); return }
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

    func captureDevicePoint(at position: CGPoint) -> CGPoint? {
        guard bounds.contains(position), previewLayer.connection?.isEnabled == true else { return nil }
        let point = previewLayer.captureDevicePointConverted(fromLayerPoint: position)
        return CameraPointFocus.isValid(point) ? point : nil
    }
}

enum CameraPointFocus {
    static func isValid(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    static func focusMode(pointSupported: Bool, supports: (AVCaptureDevice.FocusMode) -> Bool) -> AVCaptureDevice.FocusMode? {
        guard pointSupported else { return nil }
        return [.autoFocus, .continuousAutoFocus].first(where: supports)
    }

    static func exposureMode(pointSupported: Bool, supports: (AVCaptureDevice.ExposureMode) -> Bool) -> AVCaptureDevice.ExposureMode? {
        guard pointSupported else { return nil }
        return [.continuousAutoExposure, .autoExpose].first(where: supports)
    }

    static func apply(point: CGPoint, to device: AVCaptureDevice) -> Bool {
        guard isValid(point), (try? device.lockForConfiguration()) != nil else { return false }
        defer { device.unlockForConfiguration() }
        let focus = focusMode(pointSupported: device.isFocusPointOfInterestSupported, supports: device.isFocusModeSupported)
        let exposure = exposureMode(pointSupported: device.isExposurePointOfInterestSupported, supports: device.isExposureModeSupported)
        if let focus {
            device.focusPointOfInterest = point
            device.focusMode = focus
        }
        if let exposure {
            device.exposurePointOfInterest = point
            device.exposureMode = exposure
        }
        return focus != nil || exposure != nil
    }
}
