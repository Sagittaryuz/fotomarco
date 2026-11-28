import SwiftUI

@MainActor
final class CloudUploadProgress: ObservableObject {
    static let shared = CloudUploadProgress()
    @Published private(set) var values: [UUID: Double] = [:]
    struct DestinationState: Equatable {
        let id: String
        let origin: GalleryOrigin
        let label: String
        var fraction: Double
    }
    @Published private(set) var destinations: [UUID: [String: DestinationState]] = [:]
    private var personalDestinationIDs: [UUID: Set<String>] = [:]
    private var activeDestinations: [UUID: Set<String>] = [:]
    private var businessDestinationIDs: [UUID: Set<String>] = [:]

    func prepareDestinations(_ entries: [UUID: [CloudDeliveryPlan.Delivery]]) {
        var next: [UUID: Set<String>] = [:]
        for (captureID, deliveries) in entries {
            for delivery in deliveries {
                let destination = delivery.destination
                let origin: GalleryOrigin = destination.provider == .googleDrive ? .google : .oneDrive
                let key = origin.rawValue + "/" + destination.accountHash
                next[captureID, default: []].insert(key)
                if destinations[captureID]?[key] == nil {
                    destinations[captureID, default: [:]][key] = .init(id: key, origin: origin,
                        label: origin.title, fraction: delivery.phase == .verified ? 1 : 0)
                }
                if delivery.phase == .verified { destinations[captureID]?[key]?.fraction = 1 }
            }
        }
        for (captureID, keys) in personalDestinationIDs {
            for key in keys.subtracting(next[captureID] ?? []) { destinations[captureID]?.removeValue(forKey: key) }
            if destinations[captureID]?.isEmpty == true { destinations.removeValue(forKey: captureID) }
        }
        personalDestinationIDs = next
    }

    func setDestination(_ id: UUID, destination: CloudDeliveryPlan.Destination, fraction: Double) {
        guard fraction.isFinite else { return }
        let origin: GalleryOrigin = destination.provider == .googleDrive ? .google : .oneDrive
        let key = origin.rawValue + "/" + destination.accountHash
        guard activeDestinations[id]?.contains(key) == true, let old = destinations[id]?[key], old.fraction < 1 else { return }
        let value = floor(min(0.99, max(0, fraction)) * 100) / 100
        if old.fraction != value { destinations[id]?[key]?.fraction = value }
    }

    func finishDestination(_ id: UUID, destination: CloudDeliveryPlan.Destination) {
        let origin: GalleryOrigin = destination.provider == .googleDrive ? .google : .oneDrive
        let key = origin.rawValue + "/" + destination.accountHash
        activeDestinations[id]?.remove(key)
        if destinations[id]?[key] != nil { destinations[id]?[key]?.fraction = 1 }
    }

    func startDestination(_ id: UUID, destination: CloudDeliveryPlan.Destination) {
        let origin: GalleryOrigin = destination.provider == .googleDrive ? .google : .oneDrive
        let key = origin.rawValue + "/" + destination.accountHash
        guard destinations[id]?[key] != nil else { return }
        activeDestinations[id, default: []].insert(key)
        destinations[id]?[key]?.fraction = 0
    }

    func stopDestination(_ id: UUID, destination: CloudDeliveryPlan.Destination) {
        let origin: GalleryOrigin = destination.provider == .googleDrive ? .google : .oneDrive
        let key = origin.rawValue + "/" + destination.accountHash
        activeDestinations[id]?.remove(key)
        if destinations[id]?[key] != nil { destinations[id]?[key]?.fraction = 0 }
    }

    func prepareBusinessDestinations(_ captures: [BusinessArchiveJournal.Capture]) {
        var next: [UUID: Set<String>] = [:]
        for capture in captures {
            let key = "business/" + capture.organizationID.uuidString
            next[capture.id, default: []].insert(key)
            if destinations[capture.id]?[key] == nil {
                destinations[capture.id, default: [:]][key] = .init(id: key, origin: .oneDrive,
                    label: "OneDrive · organização", fraction: 0)
            }
        }
        for (id, keys) in businessDestinationIDs {
            for key in keys.subtracting(next[id] ?? []) { destinations[id]?.removeValue(forKey: key) }
            if destinations[id]?.isEmpty == true { destinations.removeValue(forKey: id) }
        }
        businessDestinationIDs = next
    }

    func setBusinessDestination(_ capture: BusinessArchiveJournal.Capture, fraction: Double, verified: Bool = false) {
        let key = "business/" + capture.organizationID.uuidString
        guard fraction.isFinite, destinations[capture.id]?[key] != nil else { return }
        destinations[capture.id]?[key]?.fraction = verified ? 1 : floor(min(0.99, max(0, fraction)) * 100) / 100
    }
    private var active = Set<UUID>()
    private var pendingPersonal = Set<UUID>()
    private var pendingBusiness = Set<UUID>()

    func preparePending(_ ids: Set<UUID>) {
        pendingPersonal = ids
        reconcilePending()
    }

    func prepareBusinessPending(_ ids: Set<UUID>) {
        pendingBusiness = ids
        reconcilePending()
    }

    private func reconcilePending() {
        let ids = pendingPersonal.union(pendingBusiness)
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
