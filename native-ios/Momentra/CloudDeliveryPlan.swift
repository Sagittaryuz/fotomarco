import Foundation

/// Destinations are frozen when a capture is created. Changing switches later
/// must never cause an older capture to be sent to a different account.
struct CloudDeliveryPlan: Codable, Equatable, Sendable {
    enum Provider: String, Codable, Sendable { case googleDrive, oneDrive }
    enum Phase: String, Codable, Sendable { case pending, uncertain, verified }

    struct Destination: Codable, Hashable, Sendable {
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

    struct Delivery: Codable, Equatable, Sendable {
        let destination: Destination
        private(set) var phase: Phase = .pending
        private(set) var originalID: String?
        private(set) var stampedID: String?

        init(destination: Destination) { self.destination = destination }

        mutating func markUncertain() {
            guard phase == .pending else { return }
            phase = .uncertain
        }

        mutating func confirm(originalID: String?, stampedID: String) {
            guard phase == .pending, originalID?.isEmpty != true, !stampedID.isEmpty else { return }
            self.originalID = originalID
            self.stampedID = stampedID
            phase = .verified
        }
    }

    var isValidNewPlan: Bool {
        let destinations = deliveries.map(\.destination)
        return (keepLocal || !destinations.isEmpty) && Set(destinations).count == destinations.count
            && deliveries.allSatisfy {
                $0.phase == .pending && $0.originalID == nil && $0.stampedID == nil
                    && Destination(provider: $0.destination.provider, accountHash: $0.destination.accountHash) != nil
            }
    }

    let keepLocal: Bool
    private let keepOriginal: Bool?
    var keepsOriginal: Bool { keepOriginal ?? true }
    private(set) var deliveries: [Delivery]

    init?(keepLocal: Bool, destinations: [Destination], keepOriginal: Bool = true) {
        guard keepLocal || !destinations.isEmpty, Set(destinations).count == destinations.count else { return nil }
        self.keepLocal = keepLocal
        self.keepOriginal = keepOriginal ? nil : false
        self.deliveries = destinations.map { Delivery(destination: $0) }
    }

    mutating func markUncertain(destination: Destination) {
        guard let index = deliveries.firstIndex(where: { $0.destination == destination }) else { return }
        deliveries[index].markUncertain()
    }

    mutating func confirm(destination: Destination, originalID: String?, stampedID: String) {
        guard keepsOriginal == (originalID != nil), originalID != stampedID,
              let index = deliveries.firstIndex(where: { $0.destination == destination }) else { return }
        deliveries[index].confirm(originalID: originalID, stampedID: stampedID)
    }

    /// This is only one precondition: file integrity and remote receipts must
    /// also be checked before any caller removes a full-resolution local file.
    var destinationsVerified: Bool {
        !deliveries.isEmpty && Set(deliveries.map(\.destination)).count == deliveries.count &&
        deliveries.allSatisfy { delivery in
            delivery.phase == .verified && (keepsOriginal ? !(delivery.originalID ?? "").isEmpty : delivery.originalID == nil) &&
            !(delivery.stampedID ?? "").isEmpty &&
            Destination(provider: delivery.destination.provider, accountHash: delivery.destination.accountHash) != nil
        }
    }
}
