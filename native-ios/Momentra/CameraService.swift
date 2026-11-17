import AVFoundation
import Photos
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "br.com.momentra.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var input: AVCaptureDeviceInput?
    private var microphoneInput: AVCaptureDeviceInput?
    private var configured = false
    private var wantsSession = false
    private var startingRecording = false
    private var stopRequested = false
    private var pendingStamp: StampSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var ready = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isSwitching = false
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishingRecording = false
    @Published private(set) var videoAvailable = false
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
        let supportsVideo = session.canAddOutput(movieOutput)
        if supportsVideo { session.addOutput(movieOutput) }
        input = candidate
        configured = true
        DispatchQueue.main.async { self.hasFlash = device.hasFlash; self.videoAvailable = supportsVideo }
    }

    func stop() {
        queue.async {
            self.wantsSession = false
            if self.movieOutput.isRecording || self.startingRecording {
                self.stopRequested = true
                if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
                DispatchQueue.main.async { self.isRecording = false; self.isFinishingRecording = true }
            } else if self.session.isRunning { self.session.stopRunning() }
        }
        DispatchQueue.main.async { self.ready = false }
    }

    func capture(snapshot: StampSnapshot?) {
        guard ready, !isCapturing, !isSwitching, !isRecording, !isFinishingRecording else { return }
        isCapturing = true
        let selectedFlash = flashMode
        queue.async {
            guard self.wantsSession, self.session.isRunning else {
                DispatchQueue.main.async { self.isCapturing = false }
                return
            }
            let settings = AVCapturePhotoSettings()
            self.pendingStamp = snapshot
            if self.input?.device.hasFlash == true,
               self.photoOutput.supportedFlashModes.contains(selectedFlash) {
                settings.flashMode = selectedFlash
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func flipCamera() {
        guard ready, !isCapturing, !isSwitching, !isRecording, !isFinishingRecording else { return }
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
                    if self.session.outputs.contains(self.movieOutput) { self.session.removeOutput(self.movieOutput) }
                    if let microphone = self.microphoneInput { self.session.removeInput(microphone); self.microphoneInput = nil }
                    DispatchQueue.main.async { self.ready = false }
                }
                self.session.commitConfiguration()
                self.report("Não foi possível trocar de câmera.")
            }
        }
    }

    func startRecording() {
        guard ready, videoAvailable, !isCapturing, !isSwitching, !isRecording, !isFinishingRecording else { return }
        // Lock immediately, including while the permission sheet is visible.
        isFinishingRecording = true
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            guard let self else { return }
            self.queue.async {
                guard allowed, self.wantsSession, self.session.isRunning else {
                    if !allowed { self.report("Permita o acesso ao microfone para gravar vídeos com áudio.") }
                    DispatchQueue.main.async { self.isFinishingRecording = false }
                    return
                }
                do {
                    if self.microphoneInput == nil {
                        guard let microphone = AVCaptureDevice.default(for: .audio) else { throw CameraError.microphone }
                        let audio = try AVCaptureDeviceInput(device: microphone)
                        self.session.beginConfiguration()
                        guard self.session.canAddInput(audio) else {
                            self.session.commitConfiguration()
                            throw CameraError.microphone
                        }
                        self.session.addInput(audio)
                        self.microphoneInput = audio
                        self.session.commitConfiguration()
                    }
                    let base = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    let directory = base.appendingPathComponent("Videos", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                    let file = directory.appendingPathComponent(UUID().uuidString + ".mov")
                    self.stopRequested = false
                    self.startingRecording = true
                    self.movieOutput.startRecording(to: file, recordingDelegate: self)
                    DispatchQueue.main.async { self.isFinishingRecording = false; self.isRecording = true }
                } catch {
                    self.report(error.localizedDescription)
                    DispatchQueue.main.async { self.isFinishingRecording = false }
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording, !isFinishingRecording else { return }
        isRecording = false
        isFinishingRecording = true
        queue.async {
            self.stopRequested = true
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async {
            self.startingRecording = false
            if self.stopRequested || !self.wantsSession { self.movieOutput.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            self.startingRecording = false
            self.stopRequested = false
            if !self.wantsSession && self.session.isRunning { self.session.stopRunning() }
            let completed = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            guard completed, FileManager.default.fileExists(atPath: outputFileURL.path) else {
                self.report("A gravação não foi concluída. O arquivo disponível permanece no aplicativo.")
                DispatchQueue.main.async { self.isRecording = false; self.isFinishingRecording = false }
                return
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    self.report("O vídeo permanece no aplicativo; permita o acesso ao Fotos para salvá-lo na biblioteca.")
                    DispatchQueue.main.async { self.isRecording = false; self.isFinishingRecording = false }
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: outputFileURL, options: nil)
                }) { success, _ in
                    if !success { self.report("O vídeo permanece no aplicativo, mas não foi salvo no Fotos.") }
                    DispatchQueue.main.async { self.isRecording = false; self.isFinishingRecording = false }
                }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            queue.async { self.pendingStamp = nil }
            report("Não foi possível capturar a foto.")
            DispatchQueue.main.async { self.isCapturing = false }
            return
        }
        queue.async {
            let snapshot = self.pendingStamp
            self.pendingStamp = nil
            do {
                let base = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let originals = base.appendingPathComponent("Originals", isDirectory: true)
                try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                let source = CGImageSourceCreateWithData(data as CFData, nil)
                let type = source.flatMap { CGImageSourceGetType($0) }.map { $0 as String }.flatMap { UTType($0) }
                let suffix = type?.preferredFilenameExtension ?? "image"
                try data.write(to: originals.appendingPathComponent(UUID().uuidString + "." + suffix), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                self.report("Não foi possível preservar a foto original. Libere espaço e tente novamente.")
                DispatchQueue.main.async { self.isCapturing = false }
                return
            }
            guard let snapshot else { self.savePhoto(data); return }
            StampMap.load(snapshot: snapshot, queue: self.queue) { map in
                if snapshot.mapEnabled && snapshot.location != nil && map == nil {
                    self.report("Mapa indisponível. A foto será salva com as demais informações.")
                }
                let rendered = StampRenderer.render(data, snapshot: snapshot, map: map)
                if rendered == nil { self.report("Não foi possível aplicar o carimbo; a foto original será salva.") }
                self.savePhoto(rendered ?? data)
            }
        }
    }

    private func savePhoto(_ data: Data) {
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
        case unavailable, configuration, microphone
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Câmera indisponível neste aparelho."
            case .configuration: return "Não foi possível configurar a câmera."
            case .microphone: return "Microfone indisponível para gravação."
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
