import BackgroundTasks
import Foundation
import UIKit

enum CloudBackgroundPolicy {
    static func shouldSchedule(_ phases: [CloudCapturePhase]) -> Bool {
        phases.contains { $0 == .awaitingPhoto || $0 == .ready || $0 == .verified || $0 == .cleaning }
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
                let summary = await CloudArchiveDelivery.shared.drain()
                completion.finish(!Task.isCancelled && summary?.needsAttention == false)
            }
            processing.expirationHandler = {
                work.cancel()
                completion.finish(false)
            }
        }
    }

    static func scheduleIfNeeded() {
        guard let journal = try? CloudArchiveJournal.documents() else { return }
        if let ids = try? journal.ids(), !ids.contains(where: { (try? journal.read($0).finished) != true }) { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancelPending() {
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
