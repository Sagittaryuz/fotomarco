import Foundation

/// The preference stores only the account hash, never Google credentials.
enum CloudStoragePreference {
    static let key = "native.cloud.only.ownerHash"

    static func selectedHash(defaults: UserDefaults = .standard) -> String? {
        guard let value = defaults.string(forKey: key), value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return value
    }

    static func enabled(for owner: String, defaults: UserDefaults = .standard) -> Bool {
        !owner.isEmpty && selectedHash(defaults: defaults) == CloudCaptureQueue.ownerHash(owner)
    }

    static func enable(owner: String, defaults: UserDefaults = .standard) {
        guard !owner.isEmpty else { return }
        defaults.set(CloudCaptureQueue.ownerHash(owner), forKey: key)
    }

    static func disable(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}
