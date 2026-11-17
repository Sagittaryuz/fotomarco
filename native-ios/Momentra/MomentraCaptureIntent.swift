import AppIntents

/// Shared by the app, capture extension, and control widget targets.
@available(iOS 18.0, *)
struct MomentraCaptureIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "Abrir câmera do Momentra"
    static let description = IntentDescription("Abrir o Momentra para capturar fotos.")

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app opens directly to CameraScreen after its first-run setup.
        .result()
    }
}
