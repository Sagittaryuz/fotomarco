import SwiftUI

@MainActor
final class CloudUploadProgress: ObservableObject {
    static let shared = CloudUploadProgress()
    @Published private(set) var values: [UUID: Double] = [:]
    private var active = Set<UUID>()

    func preparePending(_ ids: Set<UUID>) {
        for id in ids where values[id] == nil { values[id] = 0 }
        for id in Array(values.keys) where !ids.contains(id) && !active.contains(id) && values[id] != 1 {
            values.removeValue(forKey: id)
        }
    }

    func start(_ id: UUID) { active.insert(id); values[id] = 0 }

    func set(_ id: UUID, fraction: Double) {
        guard active.contains(id), let previous = values[id], previous < 1 else { return }
        guard fraction.isFinite else { return }
        let percentage = floor(min(0.99, max(0, fraction)) * 100) / 100
        guard percentage != previous else { return }
        values[id] = percentage
    }

    func finish(_ id: UUID) {
        active.remove(id)
        values[id] = 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if values[id] == 1 { values.removeValue(forKey: id) }
        }
    }

    func stop(_ id: UUID) { active.remove(id); values[id] = 0 }
    func discard(_ id: UUID) { active.remove(id); values.removeValue(forKey: id) }
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

/// The remaining dark sector shrinks clockwise from the top of the thumbnail.
struct CloudUploadRemainingMask: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let value = progress.isFinite ? min(1, max(0, progress)) : 0
        guard value > 0 else { return Path(rect) }
        guard value < 1 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = hypot(rect.width, rect.height)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(-90 + value * 360), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct CloudUploadIndicator: View {
    let value: Double
    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var percent: Int { Int((value * 100).rounded()) }
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Rectangle().fill(.black.opacity(0.88))
                    .mask {
                        CloudUploadRemainingMask(progress: value)
                    }
                Text("\(percent)%")
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
            .accessibilityLabel("Envio à nuvem: \(percent) por cento")
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
