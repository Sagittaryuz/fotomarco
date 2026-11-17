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
    private var pendingAspect: PhotoAspect = .standard
    private var pendingPhotoSaveToPhotos = true
    private var pendingVideoSaveToPhotos = true
    private var captureRotation: CGFloat = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var ready = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isSwitching = false
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishingRecording = false
    @Published private(set) var videoAvailable = false
    @Published private(set) var zoomOptions: [CGFloat] = []
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var zoomRange: ClosedRange<CGFloat> = 1...1
    @Published private(set) var hasFlash = false
    @Published private(set) var activeDevice: AVCaptureDevice?
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
        guard let device = preferredCamera(position: .back) else {
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
        DispatchQueue.main.async { self.hasFlash = device.hasFlash; self.videoAvailable = supportsVideo; self.activeDevice = device }
        resetZoom(for: device)
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

    func capture(snapshot: StampSnapshot?, aspect: PhotoAspect, saveToPhotos: Bool) {
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
            self.pendingAspect = aspect
            self.pendingPhotoSaveToPhotos = saveToPhotos
            self.applyCaptureRotation(to: self.photoOutput.connection(with: .video))
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
            guard let device = self.preferredCamera(position: position),
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
                DispatchQueue.main.async { self.hasFlash = device.hasFlash; self.activeDevice = device }
                self.resetZoom(for: device)
            } else {
                if self.session.canAddInput(previous) { self.session.addInput(previous) }
                else {
                    self.input = nil
                    self.configured = false
                    self.session.removeOutput(self.photoOutput)
                    if self.session.outputs.contains(self.movieOutput) { self.session.removeOutput(self.movieOutput) }
                    if let microphone = self.microphoneInput { self.session.removeInput(microphone); self.microphoneInput = nil }
                    DispatchQueue.main.async { self.ready = false; self.activeDevice = nil }
                }
                self.session.commitConfiguration()
                self.report("Não foi possível trocar de câmera.")
            }
        }
    }

    func updateCaptureRotation(_ angle: CGFloat) {
        queue.async { self.captureRotation = angle }
    }

    private func applyCaptureRotation(to connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoRotationAngleSupported(captureRotation) else { return }
        connection.videoRotationAngle = captureRotation
    }

    private func preferredCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        return types.lazy.compactMap { AVCaptureDevice.default($0, for: .video, position: position) }.first
    }

    private func zoomScale(for device: AVCaptureDevice) -> ZoomScale {
        let constituents = device.constituentDevices
        let switches = device.virtualDeviceSwitchOverVideoZoomFactors
        let wideIndex = constituents.firstIndex { $0.deviceType == .builtInWideAngleCamera }
        let wideFactor: CGFloat
        if let index = wideIndex, index > 0, switches.indices.contains(index - 1) {
            wideFactor = CGFloat(truncating: switches[index - 1])
        } else {
            wideFactor = 1
        }
        return ZoomScale(wideFactor: wideFactor, minimum: device.minAvailableVideoZoomFactor, maximum: device.maxAvailableVideoZoomFactor)
    }

    private func resetZoom(for device: AVCaptureDevice) {
        let scale = zoomScale(for: device)
        if let factor = scale.deviceFactor(for: 1) {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
            } catch { report("Não foi possível ajustar o zoom inicial.") }
        }
        publishZoom(for: device)
    }

    private func publishZoom(for device: AVCaptureDevice) {
        let scale = zoomScale(for: device)
        let options = scale.options
        let current = device.videoZoomFactor / scale.wideFactor
        let minimum = scale.minimum / scale.wideFactor
        let maximum = max(minimum, min(scale.maximum / scale.wideFactor, 40))
        DispatchQueue.main.async { self.zoomOptions = options; self.zoomFactor = current; self.zoomRange = minimum...maximum }
    }

    func setZoom(_ factor: CGFloat) {
        guard ready, !isSwitching, !isCapturing, !isFinishingRecording else { return }
        queue.async {
            guard let device = self.input?.device,
                  let deviceFactor = self.zoomScale(for: device).deviceFactor(for: factor) else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = deviceFactor
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.zoomFactor = factor }
            } catch { self.report("Não foi possível alterar o zoom da câmera.") }
        }
    }

    func startRecording(saveToPhotos: Bool) {
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
                    self.pendingVideoSaveToPhotos = saveToPhotos
                    self.startingRecording = true
                    self.applyCaptureRotation(to: self.movieOutput.connection(with: .video))
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
            guard self.pendingVideoSaveToPhotos else {
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
            let aspect = self.pendingAspect
            let saveToPhotos = self.pendingPhotoSaveToPhotos
            let captureID = UUID()
            self.pendingStamp = nil
            do {
                let base = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let originals = base.appendingPathComponent("Originals", isDirectory: true)
                try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                let source = CGImageSourceCreateWithData(data as CFData, nil)
                let type = source.flatMap { CGImageSourceGetType($0) }.map { $0 as String }.flatMap { UTType($0) }
                let suffix = type?.preferredFilenameExtension ?? "image"
                try data.write(to: originals.appendingPathComponent(captureID.uuidString + "." + suffix), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                self.report("Não foi possível preservar a foto original. Libere espaço e tente novamente.")
                DispatchQueue.main.async { self.isCapturing = false }
                return
            }
            guard let snapshot else {
                guard let rendered = StampRenderer.render(data, aspect: aspect, snapshot: nil) else {
                    self.report("Não foi possível ajustar a proporção. O original está disponível em Capturas.")
                    DispatchQueue.main.async { self.isCapturing = false }
                    return
                }
                self.savePhoto(rendered, captureID: captureID, saveToPhotos: saveToPhotos)
                return
            }
            StampMap.load(snapshot: snapshot, queue: self.queue) { map in
                if snapshot.mapEnabled && snapshot.location != nil && map == nil {
                    self.report("Mapa indisponível. A foto será salva com as demais informações.")
                }
                StampAddress.load(snapshot: snapshot, queue: self.queue) { address in
                    if snapshot.addressEnabled && snapshot.location != nil && address == nil {
                        self.report("Endereço indisponível. A foto será salva com as demais informações.")
                    }
                    guard let rendered = StampRenderer.render(data, aspect: aspect, snapshot: snapshot, map: map, address: address) else {
                        self.report("Não foi possível compor a foto. O original está disponível em Capturas.")
                        DispatchQueue.main.async { self.isCapturing = false }
                        return
                    }
                    self.savePhoto(rendered, captureID: captureID, saveToPhotos: saveToPhotos)
                }
            }
        }
    }

    private func savePhoto(_ data: Data, captureID: UUID, saveToPhotos: Bool) {
        do { _ = try ProcessedFileStore.save(data, captureID: captureID) }
        catch {
            report("Não foi possível preservar a foto processada. O original está disponível em Capturas.")
            DispatchQueue.main.async { self.isCapturing = false }
            return
        }
        guard saveToPhotos else {
            DispatchQueue.main.async { self.isCapturing = false }
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.report("Permita salvar fotos nos Ajustes do iPhone. A foto processada e o original estão em Capturas.")
                DispatchQueue.main.async { self.isCapturing = false }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }) { success, _ in
                if !success { self.report("Não foi possível salvar no Fotos. A foto processada e o original estão em Capturas.") }
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
    let device: AVCaptureDevice?
    let onCaptureRotation: (CGFloat) -> Void
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.update(device: device, onCaptureRotation: onCaptureRotation)
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {
        view.previewLayer.session = session
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
}
