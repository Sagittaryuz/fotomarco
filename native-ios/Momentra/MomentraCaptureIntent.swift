import AppIntents

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
}

/// Shared by the app, capture extension, and control widget targets.
@available(iOS 18.0, *)
struct MomentraCaptureIntent: CameraCaptureIntent {
    typealias AppContext = MomentraCaptureContext
    static let title: LocalizedStringResource = "Abrir câmera do Momentra"
    static let description = IntentDescription("Abrir o Momentra para capturar fotos.")

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app opens directly to CameraScreen after its first-run setup.
        .result()
    }
}
