import ExtensionKit
import LockedCameraCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct MomentraCaptureExtension: LockedCameraCaptureExtension {
    @State private var captureContext: MomentraCaptureContext?
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedCaptureView(session: session, captureContext: captureContext)
                .ignoresSafeArea()
                .task { captureContext = try? await MomentraCaptureIntent.appContext }
        }
    }
}

/// Experimental capture surface. Files remain in the system session directory
/// until the containing app imports them; this is not the final Momentra UI.
private struct LockedCaptureView: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession
    let captureContext: MomentraCaptureContext?

    func makeCoordinator() -> Coordinator { Coordinator(directory: session.sessionContentURL, captureContext: captureContext) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {
        context.coordinator.captureContext = captureContext
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let directory: URL
        var captureContext: MomentraCaptureContext?
        init(directory: URL, captureContext: MomentraCaptureContext?) {
            self.directory = directory
            self.captureContext = captureContext
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let jpeg = image.jpegData(compressionQuality: 0.95) else {
                showError(picker); return
            }
            let id = UUID().uuidString
            let capturedAt = Date()
            let settings = captureContext
            do { try jpeg.write(to: directory.appendingPathComponent(id).appendingPathExtension("jpg"), options: .atomic) }
            catch { showError(picker); return }
            guard let settings, settings.stampEnabled else { return }
            let directory = directory
            Task.detached(priority: .userInitiated) {
                let snapshot = StampSnapshot(capturedAt: capturedAt, gpsEnabled: settings.gpsEnabled,
                    title: settings.title, note: settings.note, compact: settings.compact,
                    position: settings.position, horizontal: settings.horizontal, longDate: settings.longDate,
                    fontStyle: settings.fontStyle, location: nil, heading: nil)
                let aspect = PhotoAspect(rawValue: settings.aspect) ?? .standard
                guard let stamped = StampRenderer.render(jpeg, aspect: aspect, snapshot: snapshot) else { return }
                let processed = directory.appendingPathComponent("Processed", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
                    try stamped.write(to: processed.appendingPathComponent(id).appendingPathExtension("jpg"), options: .atomic)
                } catch { return }
            }
        }

        private func showError(_ picker: UIImagePickerController) {
            let alert = UIAlertController(title: "Não foi possível guardar a foto", message: "Tente fotografar novamente.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            picker.present(alert, animated: true)
        }
    }
}
