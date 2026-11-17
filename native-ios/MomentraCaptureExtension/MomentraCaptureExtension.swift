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
        let overlay = UIHostingController(rootView: LockedStampOverlay(settings: captureContext))
        overlay.view.backgroundColor = .clear
        overlay.view.isUserInteractionEnabled = false
        overlay.view.frame = picker.view.bounds
        overlay.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        picker.cameraOverlayView = overlay.view
        context.coordinator.overlay = overlay
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {
        context.coordinator.captureContext = captureContext
        context.coordinator.overlay?.rootView = LockedStampOverlay(settings: captureContext)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let directory: URL
        var captureContext: MomentraCaptureContext?
        var overlay: UIHostingController<LockedStampOverlay>?
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

private struct LockedStampOverlay: View {
    let settings: MomentraCaptureContext?

    var body: some View {
        VStack {
            if settings?.position == "top" { Spacer().frame(height: 80) }
            else { Spacer() }
            if let settings, settings.stampEnabled {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    VStack(alignment: .leading, spacing: 4) {
                        if !settings.title.isEmpty { Text(settings.title).font(.caption.bold()) }
                        if !settings.note.isEmpty { Text(settings.note).font(.caption) }
                        Text(timeline.date, format: .dateTime.day().month().year().hour().minute().second())
                            .font(.caption.monospacedDigit())
                        Text(settings.gpsEnabled ? "Localização indisponível nesta captura" : "Localização desativada")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }
            }
            if settings?.position == "top" { Spacer() }
            else { Spacer().frame(height: 165) }
        }
    }
}
