import SwiftUI

@MainActor
final class CloudUploadProgress: ObservableObject {
    static let shared = CloudUploadProgress()
    @Published private(set) var values: [UUID: Double] = [:]

    func start(_ id: UUID) { values[id] = 0 }

    func set(_ id: UUID, fraction: Double) {
        guard let previous = values[id], previous < 1 else { return }
        values[id] = min(0.99, max(0, fraction))
    }

    func finish(_ id: UUID) {
        values[id] = 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if values[id] == 1 { values.removeValue(forKey: id) }
        }
    }

    func stop(_ id: UUID) { values.removeValue(forKey: id) }
}

/// Per-task delegate reports actual body bytes and preserves the no-redirect policy.
final class CloudUploadDelegate: NSObject, URLSessionTaskDelegate {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress(min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct CloudUploadIndicator: View {
    let value: Double
    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle().fill(.black.opacity(0.65))
                    .mask {
                        Circle().trim(from: CGFloat(value), to: 1)
                            .stroke(style: StrokeStyle(lineWidth: max(geometry.size.width, geometry.size.height) * 1.5))
                            .rotationEffect(.degrees(-90))
                    }
                Text("\(Int(value * 100))%")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(5).background(.black.opacity(0.65), in: Capsule())
                if value >= 1 { Color.white.opacity(flash ? 0.55 : 0) }
            }
            .animation(.linear(duration: 0.12), value: value)
            .onChange(of: value) { _, newValue in
                if newValue >= 1 { blink() }
            }
            .onAppear { if value >= 1 { blink() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Envio à nuvem: \(Int(value * 100)) por cento")
            .allowsHitTesting(false)
        }
    }

    private func blink() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.12)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
        }
    }
}

struct CloudUploadTile: View {
    let captureID: UUID?
    @ObservedObject private var progress = CloudUploadProgress.shared
    var body: some View {
        if let captureID, let value = progress.values[captureID] {
            CloudUploadIndicator(value: value)
        }
    }
}
