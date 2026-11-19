import UIKit

enum GalleryShareHandoff {
    static func destination(for activity: UIActivity.ActivityType?, completed: Bool, error: Error?) -> URL? {
        guard completed, error == nil else { return nil }
        switch activity?.rawValue {
        case "net.whatsapp.WhatsApp.ShareExtension":
            return URL(string: "whatsapp://app")
        default:
            return nil
        }
    }

    static func openDestination(for activity: UIActivity.ActivityType?, completed: Bool, error: Error?) {
        guard let destination = destination(for: activity, completed: completed, error: error) else { return }
        Task { @MainActor in
            UIApplication.shared.open(destination, options: [:], completionHandler: nil)
        }
    }
}
