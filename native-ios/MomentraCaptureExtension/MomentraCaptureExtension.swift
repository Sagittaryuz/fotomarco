import ExtensionKit
import LockedCameraCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct MomentraCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedCaptureView(session: session).ignoresSafeArea()
        }
    }
}

/// Experimental capture surface. Files remain in the system session directory
/// until the containing app imports them; this is not the final Momentra UI.
private struct LockedCaptureView: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession

    func makeCoordinator() -> Coordinator { Coordinator(directory: session.sessionContentURL) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let directory: URL
        init(directory: URL) { self.directory = directory }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let jpeg = image.jpegData(compressionQuality: 0.95) else {
                showError(picker); return
            }
            do {
                let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                try jpeg.write(to: target, options: .atomic)
            } catch { showError(picker) }
        }

        private func showError(_ picker: UIImagePickerController) {
            let alert = UIAlertController(title: "Não foi possível guardar a foto", message: "Tente fotografar novamente.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            picker.present(alert, animated: true)
        }
    }
}
