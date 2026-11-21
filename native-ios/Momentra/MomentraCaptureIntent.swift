import AppIntents
import Foundation

struct MomentraCaptureContext: Codable, Equatable, Sendable {
    let stampEnabled: Bool
    let gpsEnabled: Bool
    let title: String
    let note: String
    let compact: Bool
    let position: String
    let horizontal: String
    let longDate: Bool
    let fontStyle: String
    let aspect: String
    let saveToPhotos: Bool?
    var profileID: UUID? = nil
    var profileName: String? = nil
    var cloudOwnerHash: String? = nil
    var layoutData: Data? = nil
    var hasLogo: Bool? = nil
    var archivePlan: CloudDeliveryPlan? = nil
    var hapticFocusIntensity: Double? = nil
}

/// Shared by the app, capture extension, and control widget targets.
@available(iOS 18.0, *)
struct MomentraCaptureIntent: CameraCaptureIntent {
    typealias AppContext = MomentraCaptureContext
    static let title: LocalizedStringResource = "Abrir câmera do Fotomarco"
    static let description = IntentDescription("Abrir o Fotomarco para capturar fotos.")

    @MainActor
    func perform() async throws -> some IntentResult {
        // If the app is already open, leave any presented panel and reveal the camera.
        NotificationCenter.default.post(name: .momentraOpenCamera, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let momentraOpenCamera = Notification.Name("MomentraOpenCamera")
}
