import Foundation

/// Destinations are frozen when a capture is created. Changing switches later
/// must never cause an older capture to be sent to a different account.
struct CloudDeliveryPlan: Codable, Equatable {
    enum Provider: String, Codable { case googleDrive, oneDrive }
    enum Phase: String, Codable { case pending, uncertain, verified }

    struct Destination: Codable, Hashable {
        let provider: Provider
        /// Hash of the stable provider account identifier, never a token or email.
        let accountHash: String

        init?(provider: Provider, accountHash: String) {
            guard accountHash.utf8.count == 64,
                  accountHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
            self.provider = provider
            self.accountHash = accountHash
        }
    }

    struct Delivery: Codable, Equatable {
        let destination: Destination
        private(set) var phase: Phase = .pending
        private(set) var originalID: String?
        private(set) var stampedID: String?

        init(destination: Destination) { self.destination = destination }

        mutating func markUncertain() {
            guard phase == .pending else { return }
            phase = .uncertain
        }

        mutating func confirm(originalID: String, stampedID: String) {
            guard phase == .pending, !originalID.isEmpty, !stampedID.isEmpty else { return }
            self.originalID = originalID
            self.stampedID = stampedID
            phase = .verified
        }
    }

    let keepLocal: Bool
    private(set) var deliveries: [Delivery]

    init?(keepLocal: Bool, destinations: [Destination]) {
        guard keepLocal || !destinations.isEmpty, Set(destinations).count == destinations.count else { return nil }
        self.keepLocal = keepLocal
        self.deliveries = destinations.map { Delivery(destination: $0) }
    }

    mutating func markUncertain(destination: Destination) {
        guard let index = deliveries.firstIndex(where: { $0.destination == destination }) else { return }
        deliveries[index].markUncertain()
    }

    mutating func confirm(destination: Destination, originalID: String, stampedID: String) {
        guard let index = deliveries.firstIndex(where: { $0.destination == destination }) else { return }
        deliveries[index].confirm(originalID: originalID, stampedID: stampedID)
    }

    /// This is only one precondition: file integrity and remote receipts must
    /// also be checked before any caller removes a full-resolution local file.
    var destinationsVerified: Bool {
        !deliveries.isEmpty && deliveries.allSatisfy { $0.phase == .verified }
    }
}
