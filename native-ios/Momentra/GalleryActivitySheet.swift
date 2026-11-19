import SwiftUI
import UIKit

struct GalleryActivitySheet: UIViewControllerRepresentable {
    let files: [URL]
    let resource: AnyObject
    let onSuccess: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss

    nonisolated static func succeeded(completed: Bool, error: Error?) -> Bool {
        completed && error == nil
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: files, applicationActivities: nil)
        controller.completionWithItemsHandler = { [resource, dismiss, onSuccess] _, completed, _, error in
            let succeeded = Self.succeeded(completed: completed, error: error)
            withExtendedLifetime(resource) {
                Task { @MainActor in
                    if succeeded { onSuccess() }
                    dismiss()
                }
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
