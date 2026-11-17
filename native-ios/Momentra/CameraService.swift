import AVFoundation
import Photos
import SwiftUI

final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "br.com.momentra.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var wantsSession = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var ready = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isSwitching = false
    @Published private(set) var hasFlash = false
    @Published var flashMode: AVCaptureDevice.FlashMode = .off

    func start() {
        queue.async {
            self.wantsSession = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard let self else { return }
                self.queue.async {
                    guard self.wantsSession else { return }
                    guard allowed else { self.report("Permita o acesso à câmera nos Ajustes do iPhone."); return }
                    do {
                        if !self.configured { try self.configure() }
                        if !self.session.isRunning { self.session.startRunning() }
                        let running = self.session.isRunning
                        DispatchQueue.main.async { self.ready = running }
                    } catch { self.report(error.localizedDescription) }
                }
            }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unavailable
        }
        let candidate = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(candidate), session.canAddOutput(photoOutput) else { throw CameraError.configuration }
        session.addInput(candidate)
        session.addOutput(photoOutput)
        input = candidate
        configured = true
        DispatchQueue.main.async { self.hasFlash = device.hasFlash }
    }

    func stop() {
        queue.async {
            self.wantsSession = false
            if self.session.isRunning { self.session.stopRunning() }
        }
        DispatchQueue.main.async { self.ready = false }
    }

    func capture() {
        guard ready, !isCapturing, !isSwitching else { return }
        isCapturing = true
        let selectedFlash = flashMode
        queue.async {
            guard self.wantsSession, self.session.isRunning else {
                DispatchQueue.main.async { self.isCapturing = false }
                return
            }
            let settings = AVCapturePhotoSettings()
            if self.input?.device.hasFlash == true,
               self.photoOutput.supportedFlashModes.contains(selectedFlash) {
                settings.flashMode = selectedFlash
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func flipCamera() {
        guard ready, !isCapturing, !isSwitching else { return }
        isSwitching = true
        queue.async {
            defer { DispatchQueue.main.async { self.isSwitching = false } }
            guard self.wantsSession, let previous = self.input else { return }
            let position: AVCaptureDevice.Position = previous.device.position == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let replacement = try? AVCaptureDeviceInput(device: device) else {
                self.report("A outra câmera não está disponível.")
                return
            }
            self.session.beginConfiguration()
            self.session.removeInput(previous)
            if self.session.canAddInput(replacement) {
                self.session.addInput(replacement)
                self.input = replacement
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.hasFlash = device.hasFlash }
            } else {
                if self.session.canAddInput(previous) { self.session.addInput(previous) }
                else {
                    self.input = nil
                    self.configured = false
                    self.session.removeOutput(self.photoOutput)
                    DispatchQueue.main.async { self.ready = false }
                }
                self.session.commitConfiguration()
                self.report("Não foi possível trocar de câmera.")
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            report("Não foi possível capturar a foto.")
            DispatchQueue.main.async { self.isCapturing = false }
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.report("Permita salvar fotos nos Ajustes do iPhone.")
                DispatchQueue.main.async { self.isCapturing = false }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }) { success, _ in
                if !success { self.report("Não foi possível salvar a foto.") }
                DispatchQueue.main.async { self.isCapturing = false }
            }
        }
    }

    func clearError() { errorMessage = nil }

    private func report(_ text: String) { DispatchQueue.main.async { self.errorMessage = text } }

    private enum CameraError: LocalizedError {
        case unavailable, configuration
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Câmera indisponível neste aparelho."
            case .configuration: return "Não foi possível configurar a câmera."
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) { view.previewLayer.session = session }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
