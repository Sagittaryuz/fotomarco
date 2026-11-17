import AVFoundation
import SwiftUI
import UIKit

final class LockedCameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "br.com.momentra.locked-camera")
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var scale: ZoomScale?
    private var destination: URL?
    private var stampContext: MomentraCaptureContext?
    @Published var zoomOptions: [CGFloat] = []
    @Published var ready = false
    @Published var capturing = false
    @Published var error: String?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configure() }
                else { DispatchQueue.main.async { self?.error = "Permita o acesso à câmera para fotografar." } }
            }
        default: error = "Permita o acesso à câmera nos Ajustes do iPhone."
        }
    }

    private func configure() {
        queue.async {
            if self.session.inputs.isEmpty {
                guard let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                    let input = try? AVCaptureDeviceInput(device: device),
                    self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                    DispatchQueue.main.async { self.error = "Não foi possível iniciar a câmera." }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.session.addInput(input)
                self.session.addOutput(self.output)
                self.session.commitConfiguration()
                self.device = device
                let wide: CGFloat = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1
                self.scale = ZoomScale(wideFactor: wide, minimum: device.minAvailableVideoZoomFactor, maximum: device.maxAvailableVideoZoomFactor)
                if let factor = self.scale?.deviceFactor(for: 1), (try? device.lockForConfiguration()) != nil {
                    device.videoZoomFactor = factor
                    device.unlockForConfiguration()
                }
            }
            self.session.startRunning()
            DispatchQueue.main.async { self.zoomOptions = self.scale?.options ?? []; self.ready = self.session.isRunning }
        }
    }

    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func setZoom(_ value: CGFloat) {
        queue.async {
            guard let device = self.device, let factor = self.scale?.deviceFactor(for: value) else { return }
            do { try device.lockForConfiguration(); device.videoZoomFactor = factor; device.unlockForConfiguration() }
            catch { DispatchQueue.main.async { self.error = "Não foi possível ajustar o zoom." } }
        }
    }

    func capture(directory: URL, context: MomentraCaptureContext?) {
        guard ready, !capturing else { return }
        capturing = true
        queue.async {
            self.destination = directory
            self.stampContext = context
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { DispatchQueue.main.async { self.capturing = false } }
        guard error == nil, let jpeg = photo.fileDataRepresentation(), let directory = destination else {
            DispatchQueue.main.async { self.error = "Não foi possível capturar a foto." }; return
        }
        let id = UUID().uuidString
        do { try jpeg.write(to: directory.appendingPathComponent(id).appendingPathExtension("jpg"), options: .atomic) }
        catch { DispatchQueue.main.async { self.error = "Não foi possível guardar a foto." }; return }
        guard let context = stampContext, context.stampEnabled else { return }
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: context.gpsEnabled, title: context.title,
            note: context.note, compact: context.compact, position: context.position, horizontal: context.horizontal,
            longDate: context.longDate, fontStyle: context.fontStyle, location: nil, heading: nil)
        let aspect = PhotoAspect(rawValue: context.aspect) ?? .standard
        guard let stamped = StampRenderer.render(jpeg, aspect: aspect, snapshot: snapshot) else {
            DispatchQueue.main.async { self.error = "A foto original foi salva, mas não foi possível aplicar o carimbo." }; return
        }
        do {
            let processed = directory.appendingPathComponent("Processed", isDirectory: true)
            try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
            try stamped.write(to: processed.appendingPathComponent(id).appendingPathExtension("jpg"), options: .atomic)
        } catch { DispatchQueue.main.async { self.error = "A foto original foi salva, mas não foi possível guardar a cópia carimbada." } }
    }
}

struct LockedCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> LockedPreviewView {
        let view = LockedPreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: LockedPreviewView, context: Context) {}
}

final class LockedPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
