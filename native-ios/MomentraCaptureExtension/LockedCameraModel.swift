import AVFoundation
import BackgroundTasks
import CoreLocation
import Photos
import SwiftUI
import UIKit

final class LockedCameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "br.com.momentra.locked-camera")
    private let output = AVCapturePhotoOutput()
    private let processing = DispatchQueue(label: "br.com.momentra.locked-camera.photos", qos: .utility)
    private var device: AVCaptureDevice?
    private var scale: ZoomScale?
    private var destination: URL?
    private var stampContext: MomentraCaptureContext?
    private var capturedLocation: CLLocation?
    private var capturedHeading: CLHeading?
    private var capturedAt = Date()
    private var captureRotation: CGFloat = 0
    @Published var activeDevice: AVCaptureDevice?
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
                let switches = device.virtualDeviceSwitchOverVideoZoomFactors
                let wideIndex = device.constituentDevices.firstIndex { $0.deviceType == .builtInWideAngleCamera }
                let wide: CGFloat
                if let index = wideIndex, index > 0, switches.indices.contains(index - 1) {
                    wide = CGFloat(truncating: switches[index - 1])
                } else { wide = 1 }
                self.scale = ZoomScale(wideFactor: wide, minimum: device.minAvailableVideoZoomFactor, maximum: device.maxAvailableVideoZoomFactor)
                if let factor = self.scale?.deviceFactor(for: 1), (try? device.lockForConfiguration()) != nil {
                    device.videoZoomFactor = factor
                    device.unlockForConfiguration()
                }
            }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.activeDevice = self.device
                self.zoomOptions = self.scale?.options ?? []
                self.ready = self.session.isRunning
            }
        }
    }

    func stop() {
        ready = false
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func updateCaptureRotation(_ angle: CGFloat) { queue.async { self.captureRotation = angle } }

    func focus(at point: CGPoint, device: AVCaptureDevice, completion: @escaping (Bool) -> Void) {
        queue.async {
            let accepted = self.session.isRunning && !self.session.isInterrupted &&
                self.device === device && CameraPointFocus.apply(point: point, to: device)
            DispatchQueue.main.async { completion(accepted) }
        }
    }

    func setZoom(_ value: CGFloat) {
        queue.async {
            guard let device = self.device, let factor = self.scale?.deviceFactor(for: value) else { return }
            do { try device.lockForConfiguration(); device.videoZoomFactor = factor; device.unlockForConfiguration() }
            catch { DispatchQueue.main.async { self.error = "Não foi possível ajustar o zoom." } }
        }
    }

    func capture(directory: URL, context: MomentraCaptureContext?, location: CLLocation?, heading: CLHeading?) {
        guard ready, !capturing else { return }
        capturing = true
        let requestedAt = Date()
        queue.async {
            self.destination = directory
            self.stampContext = context
            self.capturedLocation = location
            self.capturedHeading = heading
            self.capturedAt = requestedAt
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(self.captureRotation) {
                connection.videoRotationAngle = self.captureRotation
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .speed
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async {
            guard error == nil, let directory = self.destination else {
                DispatchQueue.main.async {
                    self.capturing = false
                    self.error = "Não foi possível capturar a foto."
                }
                return
            }
            let context = self.stampContext
            let location = self.capturedLocation
            let heading = self.capturedHeading
            let date = self.capturedAt
            DispatchQueue.main.async { self.capturing = false }
            self.processing.async {
                guard let jpeg = photo.fileDataRepresentation() else {
                    DispatchQueue.main.async { self.error = "Não foi possível ler a foto capturada." }
                    return
                }
                self.processPhoto(jpeg, in: directory, context: context, location: location,
                                  heading: heading, capturedAt: date)
            }
        }
    }

    private func processPhoto(_ jpeg: Data, in directory: URL, context: MomentraCaptureContext?,
                              location: CLLocation?, heading: CLHeading?, capturedAt: Date) {
        let id = UUID().uuidString
        do { try jpeg.write(to: directory.appendingPathComponent(id).appendingPathExtension("jpg"), options: .atomic) }
        catch { DispatchQueue.main.async { self.error = "Não foi possível guardar a foto." }; return }
        var canScheduleCloud = false
        if let context, let captureID = UUID(uuidString: id) {
            do {
                let metadataDir = directory.appendingPathComponent("Metadata", isDirectory: true)
                try FileManager.default.createDirectory(at: metadataDir, withIntermediateDirectories: true)
                let metadata = LockedCaptureMetadata(captureID: captureID, capturedAt: capturedAt,
                    profileID: context.profileID, profileName: context.profileName,
                    cloudOwnerHash: context.cloudOwnerHash, archivePlan: context.archivePlan)
                guard metadata.isValid(for: captureID) else { throw CocoaError(.fileWriteInvalidFileName) }
                try JSONEncoder().encode(metadata).write(to: metadataDir.appendingPathComponent(id).appendingPathExtension("json"), options: .atomic)
                canScheduleCloud = metadata.archivePlan?.deliveries.isEmpty == false
            } catch {
                DispatchQueue.main.async {
                    self.error = "A foto foi preservada, mas seu perfil e envio à nuvem não puderam ser preparados."
                }
            }
        }
        let snapshot: StampSnapshot?
        if let context, context.stampEnabled {
            let layout = context.layoutData.flatMap { data in
                data.count <= 2000 ? try? JSONDecoder().decode(StampLayout.self, from: data) : nil
            } ?? StampLayout()
            snapshot = StampSnapshot(capturedAt: capturedAt, gpsEnabled: context.gpsEnabled, title: "",
                note: context.note, compact: context.compact, position: context.position, horizontal: context.horizontal,
                longDate: context.longDate, fontStyle: context.fontStyle, location: location, heading: heading,
                layout: layout)
        } else { snapshot = nil }
        let aspect = PhotoAspect(rawValue: context?.aspect ?? "4:3") ?? .standard
        guard let stamped = StampRenderer.render(jpeg, aspect: aspect, snapshot: snapshot) else {
            DispatchQueue.main.async { self.error = "A foto original foi salva, mas não foi possível aplicar o carimbo." }; return
        }
        do {
            let processed = directory.appendingPathComponent("Processed", isDirectory: true)
            try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
            try stamped.write(to: processed.appendingPathComponent(id).appendingPathExtension("jpg"), options: .atomic)
        } catch {
            DispatchQueue.main.async { self.error = "A foto original foi salva, mas não foi possível guardar a cópia processada." }
            return
        }
        if canScheduleCloud {
            let request = BGProcessingTaskRequest(identifier: LockedCaptureMetadata.cloudTaskIdentifier)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
            try? BGTaskScheduler.shared.submit(request)
        }
        guard context?.saveToPhotos == true else { return }
        let authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            DispatchQueue.main.async { self.error = "A foto está em Capturas. Abra o Photomark e permita salvar no Fotos para usar essa opção." }
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: stamped, options: nil)
        }) { success, _ in
            if !success { DispatchQueue.main.async { self.error = "A foto está em Capturas, mas não foi possível salvá-la no Fotos." } }
        }
    }
}
