import Foundation
import Combine
import UIKit
import UniformTypeIdentifiers

/// Prepares complete, full-resolution session images before replacing the pasteboard.
@MainActor final class SessionClipboardCoordinator: ObservableObject {
    @Published var failure: String?
    private var pending: [UUID: [URL]] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func record(_ file: URL, sessionID: UUID?) {
        guard let sessionID, pending[sessionID] != nil else { return }
        if pending[sessionID]?.contains(file) == false { pending[sessionID]?.append(file) }
    }

    func close(sessionID: UUID, files: [URL], expectedCount: Int, workPending: @escaping @MainActor () -> Bool,
               copy: @escaping @MainActor (URL, URL) async throws -> URL) {
        guard expectedCount > 0 else { return }
        pending[sessionID] = files
        let originalChangeCount = UIPasteboard.general.changeCount
        var backgroundID: UIBackgroundTaskIdentifier = .invalid
        backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Preparar c√≥pia das capturas") { [weak self] in
            Task { @MainActor in
                self?.failure = "O iPhone interrompeu a cÛpia das fotos. Elas continuam na galeria."
                self?.tasks[sessionID]?.cancel()
                if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID); backgroundID = .invalid }
            }
        }
        tasks[sessionID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.pending[sessionID] = nil
                self.tasks[sessionID] = nil
                if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID); backgroundID = .invalid }
            }
            do {
                while workPending() {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(200))
                }
                try Task.checkCancellation()
                let files = self.pending[sessionID] ?? []
                guard files.count == expectedCount else { throw CocoaError(.fileReadUnknown) }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                var items: [[String: Any]] = []
                for (index, file) in files.enumerated() {
                    try Task.checkCancellation()
                    let target = directory.appendingPathComponent(String(index), isDirectory: true)
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    let copied = try await copy(file, target)
                    let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: copied, options: .mappedIfSafe) }.value
                    guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                    items.append([UTType.jpeg.identifier: data])
                }
                try Task.checkCancellation()
                // Do not overwrite something the user copied in another app while preparation was running.
                guard UIPasteboard.general.changeCount == originalChangeCount else {
                    self.failure = "As fotos n„o foram copiadas porque a ·rea de transferÍncia mudou. Elas continuam na galeria."
                    return
                }
                UIPasteboard.general.setItems(items, options: [.localOnly: true])
            } catch {
                if !Task.isCancelled { self.failure = "N√£o foi poss√≠vel copiar todas as fotos da sess√£o. Elas continuam dispon√≠veis na galeria." }
            }
        }
    }
}
