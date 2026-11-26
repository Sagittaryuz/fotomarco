import AVFoundation
import Vision
import UIKit
import SwiftUI

struct LiveRecognizedItem: Equatable {
    enum Kind { case qr, text }
    let kind: Kind
    let value: String
}

final class LiveRecognitionEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var item: LiveRecognizedItem?
    @Published private(set) var available = true
    let queue = DispatchQueue(label: "br.com.momentra.recognition", qos: .utility)
    private let scanQueue = DispatchQueue(label: "br.com.momentra.recognition.scan", qos: .utility)
    private var qrEnabled = false
    private var textEnabled = false
    private var lastScan = Date.distantPast
    private var misses = 0
    private var scanInFlight = false
    private var generation = 0
    private var previewFrame: ((CVPixelBuffer, CGFloat, Bool) -> Void)?

    func setPreviewFrameHandler(_ handler: @escaping (CVPixelBuffer, CGFloat, Bool) -> Void) {
        queue.async { self.previewFrame = handler }
    }

    func setEnabled(qr: Bool, text: Bool) {
        queue.async {
            guard self.qrEnabled != qr || self.textEnabled != text else { return }
            self.qrEnabled = qr
            self.textEnabled = text
            self.generation += 1
            self.lastScan = .distantPast
            self.misses = 0
            DispatchQueue.main.async { if self.item != nil { self.item = nil } }
        }
    }

    func setUnavailable() {
        DispatchQueue.main.async { self.available = false; self.item = nil }
    }

    func clear() { DispatchQueue.main.async { self.item = nil } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            previewFrame?(buffer, connection.videoRotationAngle, connection.isVideoMirrored)
        }
        guard (qrEnabled || textEnabled), !scanInFlight, Date().timeIntervalSince(lastScan) >= 1,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastScan = Date()
        scanInFlight = true
        let qr = qrEnabled, text = textEnabled, requestGeneration = generation
        scanQueue.async { [weak self] in
            let result = Self.recognize(pixelBuffer, qr: qr, text: text)
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.scanInFlight = false
                guard self.generation == requestGeneration, result.completed else { return }
                if result.item == nil { self.misses += 1 } else { self.misses = 0 }
                guard result.item != nil || self.misses >= 3 else { return }
                DispatchQueue.main.async { if self.item != result.item { self.item = result.item } }
            }
        }
    }

    private static func recognize(_ pixelBuffer: CVPixelBuffer, qr: Bool, text: Bool) -> (completed: Bool, item: LiveRecognizedItem?) {
        let barcode = VNDetectBarcodesRequest()
        barcode.symbologies = [.qr]
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        textRequest.minimumTextHeight = 0.025
        var requests: [VNRequest] = []
        if qr { requests.append(barcode) }
        if text { requests.append(textRequest) }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do { try handler.perform(requests) } catch { return (false, nil) }
        var result: LiveRecognizedItem?
        if qr, let value = barcode.results?.compactMap(\.payloadStringValue).first, !value.isEmpty {
            result = LiveRecognizedItem(kind: .qr, value: String(value.prefix(2048)))
        } else if text {
            let lines = (textRequest.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first }
                .filter { $0.confidence >= 0.6 }
                .map(\.string)
            let value = lines.prefix(8).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 3 { result = LiveRecognizedItem(kind: .text, value: String(value.prefix(1500))) }
        }
        return (true, result)
    }
}

struct LiveRecognitionBanner: View {
    @ObservedObject var engine: LiveRecognitionEngine
    let openText: (String) -> Void

    var body: some View {
        if let item = engine.item {
            Button {
                FotomarcoHaptics.play(.buttons)
                if item.kind == .qr, let url = RecognitionWebURL.parse(item.value) {
                    UIApplication.shared.open(url)
                } else {
                    openText(item.value)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: item.kind == .qr ? "qrcode" : "text.viewfinder")
                    Text(item.value.replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: item.kind == .qr && RecognitionWebURL.parse(item.value) != nil ? "arrow.up.right" : "doc.text")
                }
                .font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 10)
                .foregroundStyle(.white).background(.black.opacity(0.78), in: Capsule())
            }.buttonStyle(.plain)
                .accessibilityLabel(item.kind == .qr ? "Abrir conteúdo do QR Code" : "Selecionar texto detectado")
                .padding(.horizontal, 16).padding(.bottom, 6)
        }
    }

}

enum RecognitionWebURL {
    static func parse(_ value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = text.lowercased().hasPrefix("www.") ? "https://" + text : text
        guard let parts = URLComponents(string: candidate), let scheme = parts.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"), parts.host != nil,
              parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
}

struct RecognizedTextSelection: Identifiable {
    let id = UUID()
    let text: String
}

struct RecognizedTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text)
                .navigationTitle("Texto detectado")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Concluído") { dismiss() } }
        }
    }
}

private struct SelectableTextView: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) { view.text = text }
}
