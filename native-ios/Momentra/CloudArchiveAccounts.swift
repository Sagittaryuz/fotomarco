import Combine
import Foundation
import Security
import UIKit

@MainActor
final class CloudArchiveAccounts: ObservableObject {
    struct Account: Identifiable, Equatable {
        let id: CloudDeliveryPlan.Destination
        let label: String
        let enabled: Bool
    }

    static let shared = CloudArchiveAccounts()

    @Published private(set) var accounts: [Account] = []

    private struct Entry: Codable {
        let destination: CloudDeliveryPlan.Destination
        var label: String
        var enabled: Bool
        let clientID: String
        let connectionID: UUID
        var credential: CloudArchiveOAuth.Credential
    }

    private let oauth = CloudArchiveOAuth()
    private var entries: [Entry] = []
    private var loaded = false
    private var connecting = false
    private var refreshes: [CloudDeliveryPlan.Destination: Task<String, Error>] = [:]

    private var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "br.com.momentra.camera.storage.accounts",
            kSecAttrAccount as String: "archive-v1"
        ]
    }

    private init() {
        try? reload()
    }

    var enabledDestinations: [CloudDeliveryPlan.Destination] {
        accounts.filter(\.enabled).map(\.id)
    }

    func reload() throws {
        guard !loaded else { return }
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            loaded = true
            return
        }
        guard status == errSecSuccess, let data = result as? Data,
              let decoded = try? JSONDecoder().decode([Entry].self, from: data),
              Set(decoded.map(\.destination)).count == decoded.count,
              decoded.allSatisfy({
                  CloudDeliveryPlan.Destination(provider: $0.destination.provider,
                                                accountHash: $0.destination.accountHash) != nil
              }) else { throw CloudArchiveOAuth.Failure.keychain }
        loaded = true
        publish(decoded)
    }

    func connect(_ provider: CloudDeliveryPlan.Provider, presenting: UIWindow) async throws {
        try reload()
        guard !connecting else { throw CloudArchiveOAuth.Failure.busy }
        connecting = true
        defer { connecting = false }
        let configuration = try CloudArchiveOAuth.Configuration(provider: provider)
        let authorized = try await oauth.connect(configuration, presenting: presenting)
        let destination = authorized.destination
        var next = entries
        let index = next.firstIndex { $0.destination == destination }
        let entry = Entry(destination: destination, label: authorized.label,
                          enabled: index.map { next[$0].enabled } ?? false,
                          clientID: configuration.clientID, connectionID: UUID(),
                          credential: authorized.credential)
        if let index { next[index] = entry }
        else { next.append(entry) }
        try persist(next)
    }

    func setEnabled(_ enabled: Bool, for destination: CloudDeliveryPlan.Destination) throws {
        try reload()
        var next = entries
        guard let index = next.firstIndex(where: { $0.destination == destination }) else {
            throw CloudArchiveOAuth.Failure.disconnected
        }
        guard next[index].enabled != enabled else { return }
        next[index].enabled = enabled
        try persist(next)
    }

    /// Enablement only affects new captures. Already queued captures retain their account.
    func accessToken(for destination: CloudDeliveryPlan.Destination) async throws -> String {
        try reload()
        let configuration = try CloudArchiveOAuth.Configuration(provider: destination.provider)
        guard let entry = entries.first(where: { $0.destination == destination }),
              entry.clientID == configuration.clientID else { throw CloudArchiveOAuth.Failure.disconnected }
        if entry.credential.expiresAt.timeIntervalSinceNow > 120 {
            return entry.credential.accessToken
        }
        if let refresh = refreshes[destination] { return try await refresh.value }
        let refresh = Task { @MainActor in
            defer { self.refreshes[destination] = nil }
            let authorized = try await self.oauth.refresh(entry.credential, configuration: configuration)
            guard authorized.destination == destination else { throw CloudArchiveOAuth.Failure.wrongAccount }
            var next = self.entries
            guard let index = next.firstIndex(where: { $0.destination == destination }),
                  next[index].connectionID == entry.connectionID else {
                throw CloudArchiveOAuth.Failure.disconnected
            }
            next[index].label = authorized.label
            next[index].credential = authorized.credential
            try self.persist(next)
            return authorized.credential.accessToken
        }
        refreshes[destination] = refresh
        return try await refresh.value
    }

    private func persist(_ next: [Entry]) throws {
        let data = try JSONEncoder().encode(next)
        let query = keychainQuery
        let changes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(request as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CloudArchiveOAuth.Failure.keychain }
        publish(next)
    }

    private func publish(_ next: [Entry]) {
        entries = next
        accounts = next.map { Account(id: $0.destination, label: $0.label, enabled: $0.enabled) }
    }
}
