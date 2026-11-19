import Foundation

actor CloudGalleryCatalog {
    struct Entry: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let date: Date?
        let revision: String?
    }

    struct Snapshot: Codable, Sendable {
        let revision: UUID
        let updatedAt: Date
        let entries: [Entry]

        func needsRefresh(at date: Date = .now) -> Bool {
            let age = date.timeIntervalSince(updatedAt)
            return age < 0 || age >= 5 * 60
        }
    }

    static let shared = CloudGalleryCatalog(directory: FileManager.default.urls(for: .applicationSupportDirectory,
        in: .userDomainMask).first?.appendingPathComponent("MomentraCloudCatalog-v1", isDirectory: true))
    static let deliveryChanged = Notification.Name("MomentraCloudGalleryDeliveryChanged")

    private let directory: URL?
    private var loaded: [CloudDeliveryPlan.Destination: Snapshot] = [:]

    init(directory: URL?) { self.directory = directory }

    func snapshot(for destination: CloudDeliveryPlan.Destination) -> Snapshot? {
        if let snapshot = loaded[destination] { return snapshot }
        guard let file = fileURL(for: destination), let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        loaded[destination] = snapshot
        return snapshot
    }

    @discardableResult
    func replace(_ entries: [Entry], for destination: CloudDeliveryPlan.Destination,
                 replacing revision: UUID?, at date: Date = .now) -> Bool {
        guard !Task.isCancelled, snapshot(for: destination)?.revision == revision else { return false }
        var seen = Set<String>()
        save(Snapshot(revision: UUID(), updatedAt: date, entries: entries.filter { seen.insert($0.id).inserted }),
             for: destination)
        return true
    }

    func invalidate(_ destination: CloudDeliveryPlan.Destination, removing id: String? = nil) {
        let entries = snapshot(for: destination)?.entries ?? []
        let retained = id.map { removed in entries.filter { $0.id != removed } } ?? entries
        save(Snapshot(revision: UUID(), updatedAt: .distantPast, entries: retained), for: destination)
    }

    private func save(_ snapshot: Snapshot, for destination: CloudDeliveryPlan.Destination) {
        loaded[destination] = snapshot
        guard var directory, let file = fileURL(for: destination) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Keep the current in-memory catalog when the device can't write a local copy.
        }
    }

    private func fileURL(for destination: CloudDeliveryPlan.Destination) -> URL? {
        guard CloudDeliveryPlan.Destination(provider: destination.provider, accountHash: destination.accountHash) != nil else { return nil }
        return directory?.appendingPathComponent("\(destination.provider.rawValue)-\(destination.accountHash).json")
    }
}
