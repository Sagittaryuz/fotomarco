import AVFoundation
import Combine
import Photos
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "br.com.momentra.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let recognitionOutput = AVCaptureVideoDataOutput()
    let recognition = LiveRecognitionEngine()
    let styledPreview = CameraStylePreviewRenderer()
    private var wantsRecognition = false
    private var wantsStyledPreview = false
    private var input: AVCaptureDeviceInput?
    private var microphoneInput: AVCaptureDeviceInput?
    private var configured = false
    private var wantsSession = false
    private var startingRecording = false
    private var stopRequested = false
    private struct PhotoRequest {
        let settingsID: Int64
        let id: UUID
        let capturedAt: Date
        let snapshot: StampSnapshot?
        let aspect: PhotoAspect
        let style: MomentraPhotoStyle
        let styleAdjustments: PhotoStyleAdjustments
        let saveToPhotos: Bool
        let profile: CaptureProfileTag?
        let archivePlan: CloudDeliveryPlan?
        let businessTarget: BusinessCaptureTarget?
        let sessionID: UUID?
    }

    private struct StagedPhoto {
        let request: PhotoRequest
        let original: URL
        let root: URL
        let archiveQueued: Bool
        let businessQueued: Bool
    }

    private var pendingPhoto: PhotoRequest?
    private var pendingPhotoData: Data?
    private let photoStagingQueue = DispatchQueue(label: "br.com.momentra.photo.staging", qos: .userInitiated)
    private let photoRenderQueue = DispatchQueue(label: "br.com.momentra.photo.render", qos: .utility)
    private var stagedPhotos: [StagedPhoto] = []
    private var renderingPhoto = false
    private var photoBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    @Published private(set) var processingPhotos = 0
    let capturedPhoto = PassthroughSubject<Void, Never>()
    private var pendingVideoSaveToPhotos = true
    private var pendingVideoSnapshot: StampSnapshot?
    @Published private(set) var processingVideos = 0
    private var captureRotation: CGFloat = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var ready = false
    @Published private(set) var isCapturing = false
    struct CapturePreview {
        let image: UIImage
        let file: URL
        let sessionID: UUID?
        init(image: UIImage, file: URL, sessionID: UUID? = nil) {
            self.image = image; self.file = file; self.sessionID = sessionID
        }
    }

    let completedPhoto = PassthroughSubject<CapturePreview, Never>()
    @Published private(set) var isSwitching = false
    @Published private(set) var recordingStartedAt: ContinuousClock.Instant?
    var isRecording: Bool { recordingStartedAt != nil }
    @Published private(set) var isFinishingRecording = false
    @Published private(set) var videoAvailable = false
    @Published private(set) var zoomOptions: [CGFloat] = []
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var zoomRange: ClosedRange<CGFloat> = 1...1
    @Published private(set) var hasFlash = false
    @Published private(set) var availableFlashModes: [AVCaptureDevice.FlashMode] = [.off]
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
        defer {
            session.commitConfiguration()
            applyRecognitionDemand()
        }
        session.sessionPreset = .photo
        guard session.canAddInput(candidate), session.canAddOutput(photoOutput) else { throw CameraError.configuration }
        session.addInput(candidate)
        session.addOutput(photoOutput)
        let supportsVideo = session.canAddOutput(movieOutput)
        if supportsVideo { session.addOutput(movieOutput) }
        if session.canAddOutput(recognitionOutput) {
            recognitionOutput.alwaysDiscardsLateVideoFrames = true
            recognition.setPreviewFrameHandler { [weak styledPreview = self.styledPreview] buffer, rotation, mirrored in
                styledPreview?.submit(buffer, rotation: rotation, mirrored: mirrored)
            }
            recognitionOutput.setSampleBufferDelegate(recognition, queue: recognition.queue)
            session.addOutput(recognitionOutput)
        } else { recognition.setUnavailable() }
        input = candidate
        configured = true
        DispatchQueue.main.async { self.hasFlash = device.hasFlash; self.videoAvailable = supportsVideo; self.activeDevice = device }
        resetZoom(for: device)
        queue.async { self.publishFlashModes(for: device) }
    }

    private func publishFlashModes(for device: AVCaptureDevice) {
        let modes = device.hasFlash ? photoOutput.supportedFlashModes : [.off]
        DispatchQueue.main.async { self.availableFlashModes = modes }
    }

    func setRecognition(qr: Bool, text: Bool) {
        recognition.setEnabled(qr: qr, text: text)
        queue.async {
            self.wantsRecognition = qr || text
            self.applyRecognitionDemand()
        }
    }

    private func applyRecognitionDemand() {
        let needed = wantsRecognition || wantsStyledPreview
        if let connection = recognitionOutput.connection(with: .video), connection.isEnabled != needed {
            connection.isEnabled = needed
        }
    }

    func setStyledPreviewEnabled(_ enabled: Bool) {
        queue.async {
            guard self.wantsStyledPreview != enabled else { return }
            self.wantsStyledPreview = enabled
            self.applyRecognitionDemand()
        }
    }

    func stop() {
        queue.async {
            self.wantsSession = false
            if self.movieOutput.isRecording || self.startingRecording {
                self.stopRequested = true
                if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
                DispatchQueue.main.async { self.isFinishingRecording = true; self.recordingStartedAt = nil }
            } else if self.session.isRunning { self.session.stopRunning() }
        }
        recognition.clear()
        DispatchQueue.main.async { self.ready = false }
    }

    func canStartPhoto() -> Bool {
        guard !isCapturing, !isSwitching, !isRecording, !isFinishingRecording else { return false }
        guard ready else {
            let authorization = AVCaptureDevice.authorizationStatus(for: .video)
            errorMessage = authorization == .denied || authorization == .restricted
                ? "Permita o acesso à câmera nos Ajustes do iPhone."
                : "A câmera não está disponível para fotografar agora. Aguarde um instante e tente novamente."
            return false
        }
        return true
    }

    func capture(snapshot: StampSnapshot?, aspect: PhotoAspect, saveToPhotos: Bool, style: MomentraPhotoStyle = .natural, styleAdjustments: PhotoStyleAdjustments = .init(), profile: CaptureProfileTag? = nil, archivePlan: CloudDeliveryPlan? = nil, businessTarget: BusinessCaptureTarget? = nil, sessionID: UUID? = nil) {
        guard canStartPhoto() else { return }
        isCapturing = true
        let selectedFlash = flashMode
        let capturedAt = snapshot?.capturedAt ?? Date()
        queue.async {
            guard self.wantsSession, self.session.isRunning, !self.session.isInterrupted,
                  let connection = self.photoOutput.connection(with: .video), connection.isActive, connection.isEnabled else {
                DispatchQueue.main.async {
                    self.isCapturing = false
                    self.errorMessage = "A câmera foi interrompida. Volte ao visor e tente fotografar novamente."
                }
                return
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            self.pendingPhoto = PhotoRequest(settingsID: settings.uniqueID, id: UUID(), capturedAt: capturedAt,
                                             snapshot: snapshot, aspect: aspect, style: style, styleAdjustments: styleAdjustments, saveToPhotos: saveToPhotos,
                                             profile: profile, archivePlan: archivePlan, businessTarget: businessTarget, sessionID: sessionID)
            self.applyCaptureRotation(to: connection)
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
            defer {
                self.applyRecognitionDemand()
                DispatchQueue.main.async { self.isSwitching = false }
            }
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
                self.publishFlashModes(for: device)
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
        queue.async {
            self.captureRotation = angle
            self.applyCaptureRotation(to: self.recognitionOutput.connection(with: .video))
        }
    }

    func focus(at point: CGPoint, device: AVCaptureDevice, completion: @escaping (Bool) -> Void) {
        queue.async {
            let accepted = self.session.isRunning && !self.session.isInterrupted &&
                self.input?.device === device && CameraPointFocus.apply(point: point, to: device)
            DispatchQueue.main.async { completion(accepted) }
        }
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
                // Zoom targets the centre of the frame; continuous AF keeps tracking it
                // without restarting a focus sweep for every pinch update.
                if let mode = CameraPointFocus.zoomFocusMode(pointSupported: device.isFocusPointOfInterestSupported,
                                                             supports: device.isFocusModeSupported) {
                    let center = CGPoint(x: 0.5, y: 0.5)
                    if device.focusPointOfInterest != center || device.focusMode != mode {
                        device.focusPointOfInterest = center
                        device.focusMode = mode
                    }
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.zoomFactor = factor }
            } catch { self.report("Não foi possível alterar o zoom da câmera.") }
        }
    }

    func startRecording(saveToPhotos: Bool, snapshot: StampSnapshot? = nil, profile: CaptureProfileTag? = nil) {
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
                    let id = UUID()
                    let file = directory.appendingPathComponent(id.uuidString + ".mov")
                    if let profile {
                        do { try PhotoProfileIndex.register(captureID: id, profile: profile, captureDate: Date()) }
                        catch { self.report("O vídeo será gravado, mas não foi possível associá-lo ao perfil.") }
                    }
                    self.stopRequested = false
                    self.pendingVideoSnapshot = snapshot
                    self.pendingVideoSaveToPhotos = saveToPhotos
                    self.startingRecording = true
                    self.applyCaptureRotation(to: self.movieOutput.connection(with: .video))
                    self.movieOutput.startRecording(to: file, recordingDelegate: self)
                } catch {
                    self.report(error.localizedDescription)
                    DispatchQueue.main.async { self.isFinishingRecording = false }
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording, !isFinishingRecording else { return }
        isFinishingRecording = true
        recordingStartedAt = nil
        queue.async {
            self.stopRequested = true
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let start = ContinuousClock.now
        queue.async {
            self.startingRecording = false
            if self.stopRequested || !self.wantsSession {
                self.movieOutput.stopRecording()
            } else {
                DispatchQueue.main.async {
                    self.recordingStartedAt = start
                    self.isFinishingRecording = false
                }
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            self.startingRecording = false
            self.stopRequested = false
            if !self.wantsSession && self.session.isRunning { self.session.stopRunning() }
            let completed = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            let snapshot = self.pendingVideoSnapshot
            let saveToPhotos = self.pendingVideoSaveToPhotos
            self.pendingVideoSnapshot = nil
            DispatchQueue.main.async { self.recordingStartedAt = nil; self.isFinishingRecording = false }
            guard completed, FileManager.default.fileExists(atPath: outputFileURL.path) else {
                self.report("A gravação não foi concluída. O arquivo disponível permanece no aplicativo.")
                return
            }
            guard let snapshot else {
                if saveToPhotos { self.saveVideoToPhotos(outputFileURL, captureID: UUID(uuidString: outputFileURL.deletingPathExtension().lastPathComponent)) }
                return
            }
            DispatchQueue.main.async { self.processingVideos += 1 }
            StampMap.load(snapshot: snapshot, queue: self.queue) { map in
                StampAddress.load(snapshot: snapshot, queue: self.queue) { address in
                    let root = outputFileURL.deletingLastPathComponent().deletingLastPathComponent()
                    let destination = root.appendingPathComponent("ProcessedVideos", isDirectory: true)
                        .appendingPathComponent(outputFileURL.lastPathComponent)
                    Task {
                        defer { DispatchQueue.main.async { self.processingVideos = max(0, self.processingVideos - 1) } }
                        do {
                            try await VideoStampRenderer.export(source: outputFileURL, destination: destination,
                                                                snapshot: snapshot, map: map, address: address)
                            if saveToPhotos {
                                self.saveVideoToPhotos(destination, captureID: UUID(uuidString: destination.deletingPathExtension().lastPathComponent))
                            }
                            if snapshot.mapEnabled && snapshot.location != nil && map == nil {
                                self.report("O vídeo foi salvo sem mapa porque ele estava indisponível. O original foi preservado.")
                            } else if snapshot.addressEnabled && snapshot.location != nil && address == nil {
                                self.report("O vídeo foi salvo sem endereço porque ele estava indisponível. O original foi preservado.")
                            }
                        } catch {
                            self.report("Não foi possível aplicar o carimbo ao vídeo. O original permanece em Capturas.")
                        }
                    }
                }
            }
        }
    }

    private func saveVideoToPhotos(_ url: URL, captureID: UUID?) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.report("O vídeo permanece no aplicativo; permita o acesso ao Fotos para salvá-lo na biblioteca.")
                return
            }
            var createdAssetID: String?
            PHPhotoLibrary.shared().performChanges({
                let creation = PHAssetCreationRequest.forAsset()
                creation.addResource(with: .video, fileURL: url, options: nil)
                createdAssetID = creation.placeholderForCreatedAsset?.localIdentifier
            }) { success, _ in
                if success, let captureID, let assetID = createdAssetID {
                    try? PhotoProfileIndex.bindLocal(captureID: captureID, assetID: assetID)
                }
                if !success { self.report("Não foi possível salvar o vídeo no Fotos. O arquivo continua no aplicativo.") }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let settingsID = photo.resolvedSettings.uniqueID
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async {
            guard self.pendingPhoto?.settingsID == settingsID else { return }
            self.pendingPhotoData = data
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor settings: AVCaptureResolvedPhotoSettings, error: Error?) {
        queue.async {
            guard let request = self.pendingPhoto, request.settingsID == settings.uniqueID else { return }
            let data = self.pendingPhotoData
            self.pendingPhoto = nil
            self.pendingPhotoData = nil
            guard error == nil, let data else {
                self.report("Não foi possível capturar a foto.")
                DispatchQueue.main.async { self.isCapturing = false }
                return
            }
            DispatchQueue.main.async {
                self.beginPhotoWork()
                self.isCapturing = false
            }
            self.photoStagingQueue.async { self.stagePhoto(data, request: request) }
        }
    }

    @MainActor private func beginPhotoWork() {
        processingPhotos += 1
        guard photoBackgroundTask == .invalid else { return }
        photoBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Processar capturas do Momentra") { [weak self] in
            DispatchQueue.main.async { self?.endPhotoBackgroundTask() }
        }
    }

    @MainActor private func endPhotoBackgroundTask() {
        guard photoBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(photoBackgroundTask)
        photoBackgroundTask = .invalid
    }

    private func finishPhotoWork() {
        DispatchQueue.main.async {
            self.processingPhotos -= 1
            if self.processingPhotos == 0 { self.endPhotoBackgroundTask() }
        }
    }

    private func stagePhoto(_ data: Data, request: PhotoRequest) {
        let base: URL
        let original: URL
        let suffix: String
        do {
            base = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let originals = base.appendingPathComponent("Originals", isDirectory: true)
            try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let source = CGImageSourceCreateWithData(data as CFData, nil)
            let type = source.flatMap { CGImageSourceGetType($0) }.map { $0 as String }.flatMap { UTType($0) }
            suffix = (type?.preferredFilenameExtension ?? "image").lowercased()
            original = originals.appendingPathComponent(request.id.uuidString + "." + suffix)
            try data.write(to: original, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            report("Não foi possível preservar a foto original. Libere espaço e tente novamente.")
            finishPhotoWork()
            return
        }
        DispatchQueue.main.async { self.capturedPhoto.send(()) }
        var archiveQueued = false
        var businessQueued = false
        if let plan = request.archivePlan, !plan.deliveries.isEmpty {
            do {
                try CloudArchiveJournal(root: base).enqueue(id: request.id, date: request.capturedAt,
                    originalExtension: suffix, plan: plan, profile: request.profile)
                archiveQueued = true
            } catch {
                report("Não foi possível registrar o envio. A captura será mantida no iPhone. Confira o espaço disponível.")
            }
        }
        if let target = request.businessTarget, let profile = request.profile {
            do {
                try BusinessArchiveJournal(root: base).enqueue(id: request.id, date: request.capturedAt,
                    originalExtension: suffix, source: original, target: target, profile: profile)
                businessQueued = true
            } catch {
                report("Não foi possível registrar o envio da equipe. A foto será mantida no iPhone.")
            }
        }
        if let profile = request.profile {
            do { try PhotoProfileIndex.register(captureID: request.id, profile: profile, captureDate: request.capturedAt, location: request.snapshot?.location) }
            catch { report("A foto foi salva, mas não foi possível associá-la ao perfil.") }
        }
        let staged = StagedPhoto(request: request, original: original, root: base, archiveQueued: archiveQueued, businessQueued: businessQueued)
        photoRenderQueue.async {
            self.stagedPhotos.append(staged)
            self.renderNextPhoto()
        }
    }

    private func renderNextPhoto() {
        guard !renderingPhoto, !stagedPhotos.isEmpty else { return }
        renderingPhoto = true
        let staged = stagedPhotos.removeFirst()
        let snapshot = staged.request.snapshot
        let render: (UIImage?, String?) -> Void = { map, address in
            autoreleasepool { self.renderPhoto(staged, map: map, address: address) }
            self.renderingPhoto = false
            self.photoRenderQueue.async { self.renderNextPhoto() }
        }
        guard let snapshot else { render(nil, nil); return }
        var map: UIImage?
        var address: String?
        let enrichment = DispatchGroup()
        enrichment.enter()
        StampMap.load(snapshot: snapshot, queue: photoRenderQueue) { map = $0; enrichment.leave() }
        enrichment.enter()
        StampAddress.load(snapshot: snapshot, queue: photoRenderQueue) { address = $0; enrichment.leave() }
        enrichment.notify(queue: photoRenderQueue) { render(map, address) }
    }

    private func renderPhoto(_ staged: StagedPhoto, map: UIImage?, address: String?) {
        let request = staged.request
        let snapshot = request.snapshot
        if let snapshot, snapshot.location != nil {
            if snapshot.mapEnabled && map == nil { report("Mapa indisponível. A foto será salva com as demais informações.") }
            if snapshot.addressEnabled && address == nil { report("Endereço indisponível. A foto será salva com as demais informações.") }
        }
        guard let data = try? Data(contentsOf: staged.original, options: .mappedIfSafe),
              let rendered = StampRenderer.render(data, aspect: request.aspect, snapshot: snapshot,
                                                   map: map, address: address, style: request.style, adjustments: request.styleAdjustments) else {
            report("Não foi possível compor a foto. O original está disponível em Capturas.")
            finishPhotoWork()
            return
        }
        let processed: URL
        do { processed = try ProcessedFileStore.save(rendered, captureID: request.id, root: staged.root) }
        catch {
            report("Não foi possível preservar a foto processada. O original está disponível em Capturas.")
            finishPhotoWork()
            return
        }
        var archiveReady = false
        if staged.archiveQueued {
            do {
                try CloudArchiveJournal(root: staged.root).markReady(id: request.id)
                archiveReady = true
            } catch { report("O envio ainda não foi preparado. As cópias locais foram preservadas.") }
        }
        var businessReady = false
        if staged.businessQueued {
            do {
                try BusinessArchiveJournal(root: staged.root).markReady(id: request.id, stampedSource: processed)
                businessReady = true
            } catch { report("O envio da equipe ainda não foi preparado. As cópias locais foram preservadas.") }
        }
        if let plan = request.archivePlan, !plan.keepsOriginal, plan.deliveries.isEmpty || archiveReady {
            do {
                try CloudArchiveJournal(root: staged.root).serializeCleanup {
                    if FileManager.default.fileExists(atPath: staged.original.path) {
                        try FileManager.default.removeItem(at: staged.original)
                    }
                }
            } catch { report("A cópia sem carimbo ficou em Capturas porque não foi possível removê-la.") }
        }
        if let source = CGImageSourceCreateWithData(rendered as CFData, nil),
           let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: 1200
           ] as CFDictionary) {
            let capture = CapturePreview(image: UIImage(cgImage: preview), file: processed, sessionID: request.sessionID)
            DispatchQueue.main.async { self.completedPhoto.send(capture) }
        }
        if archiveReady || businessReady {
            CloudBackgroundScheduler.scheduleIfNeeded()
            NotificationCenter.default.post(name: .momentraCloudCaptureStaged, object: nil)
        }
        guard request.saveToPhotos else { finishPhotoWork(); return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.report("Permita salvar fotos nos Ajustes do iPhone. A foto está disponível em Capturas.")
                self.finishPhotoWork()
                return
            }
            var createdAssetID: String?
            PHPhotoLibrary.shared().performChanges({
                let creation = PHAssetCreationRequest.forAsset()
                creation.addResource(with: .photo, fileURL: processed, options: nil)
                createdAssetID = creation.placeholderForCreatedAsset?.localIdentifier
            }) { success, _ in
                if success, let assetID = createdAssetID {
                    try? PhotoProfileIndex.bindLocal(captureID: request.id, assetID: assetID)
                }
                if !success { self.report("Não foi possível salvar no Fotos. A foto está disponível em Capturas.") }
                self.finishPhotoWork()
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

extension Notification.Name { static let momentraCloudCaptureStaged = Notification.Name("MomentraCloudCaptureStaged") }
