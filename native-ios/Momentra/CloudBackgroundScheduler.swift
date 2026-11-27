import BackgroundTasks
import Foundation
import UIKit

enum CloudBackgroundPolicy {
    static func shouldSchedule(_ phases: [CloudCapturePhase]) -> Bool {
        phases.contains { $0 == .awaitingPhoto || $0 == .ready || $0 == .verified || $0 == .cleaning }
    }

    // An unreadable journal must never be mistaken for an empty queue.
    static func mayCancel(personalPending: Bool?, businessPending: Bool?) -> Bool {
        personalPending == false && businessPending == false
    }
}

/// iOS decides when this task runs and can interrupt it. The durable journal
/// and local originals remain the source of truth when a pass is interrupted.
enum CloudBackgroundScheduler {
    static let identifier = LockedCaptureMetadata.cloudTaskIdentifier

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            scheduleIfNeeded()
            let completion = CloudTaskCompletion(processing)
            let work = Task { @MainActor in
                if #available(iOS 18.0, *) { await LockedCaptureImporter.importExisting() }
                guard !Task.isCancelled else { completion.finish(false); return }
                await BusinessLegacyImportCoordinator.shared.stageIfReady()
                let summary = await CloudArchiveDelivery.shared.drain()
                let business = await BusinessArchiveDelivery.shared.drain()
                completion.finish(!Task.isCancelled && summary?.needsAttention == false && business?.needsAttention == false)
            }
            processing.expirationHandler = {
                work.cancel()
                completion.finish(false)
            }
        }
    }

    static func scheduleIfNeeded() {
        let personal = try? CloudArchiveJournal.documents()
        let business = try? BusinessArchiveJournal.documents()
        let personalPending = personal.map { journal in
            (try? journal.ids().contains(where: { (try? journal.read($0).finished) != true })) ?? true
        } ?? true
        let businessPending = business.map { journal in
            (try? journal.ids().contains(where: { (try? journal.read($0).finished) != true })) ?? true
        } ?? true
        guard personalPending || businessPending else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancelPending() {
        let personalPending: Bool? = (try? CloudArchiveJournal.documents()).flatMap { journal in
            try? journal.ids().contains(where: { (try? journal.read($0).finished) != true })
        }
        let businessPending: Bool? = (try? BusinessArchiveJournal.documents()).flatMap { journal in
            try? journal.ids().contains(where: { (try? journal.read($0).finished) != true })
        }
        guard CloudBackgroundPolicy.mayCancel(personalPending: personalPending, businessPending: businessPending) else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

private final class CloudTaskCompletion {
    private let lock = NSLock()
    private var completed = false
    private let task: BGTask

    init(_ task: BGTask) { self.task = task }

    func finish(_ success: Bool) {
        lock.lock()
        let shouldFinish = !completed
        completed = true
        lock.unlock()
        if shouldFinish { task.setTaskCompleted(success: success) }
    }
}

final class MomentraAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        CloudBackgroundScheduler.register()
        return true
    }
}
