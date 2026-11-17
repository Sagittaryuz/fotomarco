import SwiftUI
import VisionKit

struct CameraScannerView: View {
    let qrEnabled: Bool
    let textEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var result: String?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerController(qrEnabled: qrEnabled, textEnabled: textEnabled, result: $result, failure: $failure)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Leitura indisponível", systemImage: "camera.viewfinder", description: Text("Verifique o acesso à câmera e a compatibilidade do iPhone."))
                }
            }
            .navigationTitle("Ler QR e texto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Concluído") { dismiss() } }
            .alert("Conteúdo detectado", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                Button("Copiar") { if let result { UIPasteboard.general.string = result }; result = nil }
                Button("Fechar", role: .cancel) { result = nil }
            } message: { Text(result ?? "") }
            .alert("Leitura indisponível", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { dismiss() }
            } message: { Text(failure ?? "") }
        }
    }
}

private struct ScannerController: UIViewControllerRepresentable {
    let qrEnabled: Bool
    let textEnabled: Bool
    @Binding var result: String?
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator { Coordinator(result: $result) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        var types = Set<DataScannerViewController.RecognizedDataType>()
        if qrEnabled { types.insert(.barcode(symbologies: [.qr])) }
        if textEnabled { types.insert(.text()) }
        let scanner = DataScannerViewController(recognizedDataTypes: types, qualityLevel: .balanced, recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do { try scanner.startScanning() }
            catch { failure = "Não foi possível iniciar a leitura. Tente novamente." }
        }
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) { }
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var result: String?
        init(result: Binding<String?>) { _result = result }
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .barcode(let code): result = code.payloadStringValue
            case .text(let text): result = text.transcript
            @unknown default: break
            }
        }
    }
}
