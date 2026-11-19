import Foundation

struct GalleryCapacityCache {
    struct Quota: Codable, Sendable {
        let total: Int64
        let used: Int64
        var valid: Bool { total > 0 && used >= 0 }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func local(includeAppBytes: Bool) -> StorageTotals? {
        guard let data = defaults.data(forKey: localKey(includeAppBytes)),
              let totals = try? JSONDecoder().decode(StorageTotals.self, from: data) else { return nil }
        return StorageTotals(total: totals.total, used: totals.used, primary: totals.primary)
    }

    func store(_ totals: StorageTotals, includeAppBytes: Bool) {
        if let data = try? JSONEncoder().encode(totals) { defaults.set(data, forKey: localKey(includeAppBytes)) }
    }

    func quota(for destination: CloudDeliveryPlan.Destination) -> Quota? {
        guard let data = defaults.data(forKey: accountKey(destination)),
              let quota = try? JSONDecoder().decode(Quota.self, from: data), quota.valid else { return nil }
        return quota
    }

    func store(_ quota: Quota, for destination: CloudDeliveryPlan.Destination) {
        guard quota.valid, let data = try? JSONEncoder().encode(quota) else { return }
        defaults.set(data, forKey: accountKey(destination))
    }

    private func localKey(_ includesApp: Bool) -> String {
        includesApp ? "native.gallery.capacity.app.v1" : "native.gallery.capacity.volume.v1"
    }

    private func accountKey(_ destination: CloudDeliveryPlan.Destination) -> String {
        "native.gallery.capacity.\(destination.provider.rawValue).\(destination.accountHash).v1"
    }
}
