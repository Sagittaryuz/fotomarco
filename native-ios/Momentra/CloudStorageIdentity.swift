import CryptoKit
import Foundation

/// Privacy-scoped comparison of provider IDs; never compare display names or e-mails.
enum CloudStorageIdentity {
    static func fingerprint(provider: CloudDeliveryPlan.Provider, canonicalID: String, userID: String) -> String? {
        func valid(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 512 &&
            !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
        }
        guard valid(canonicalID), valid(userID) else { return nil }
        let fields = ["photomark-storage-v1", userID, provider.rawValue, canonicalID]
        let payload = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    enum Comparison: Equatable { case same, different, unknown }

    static func compare(_ first: String?, _ second: String?) -> Comparison {
        func valid(_ value: String?) -> Bool {
            guard let value else { return false }
            return value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        guard valid(first), valid(second) else { return .unknown }
        return first == second ? .same : .different
    }
}
