import Foundation
import FamilyControls

extension MonitoringLifecycle {
    static func make(storage: AppGroupStorage,
                     activity: DeviceActivityServiceProtocol = DeviceActivityService(),
                     settings: ManagedSettingsServiceProtocol = ManagedSettingsService()) -> MonitoringLifecycle {
        func selectionLoader(stage: String) -> ShieldSelectionLoader<FamilyActivitySelection> {
            ShieldSelectionLoader(load: { try storage.loadActivitySelection() },
                supported: { $0.breakLoopTokenCounts.isSupported }, apply: { settings.block($0) },
                inspected: { selection, _ in selection.logBreakLoopCounts(stage: stage) })
        }
        return MonitoringLifecycle(storage: storage, driver: MonitoringDriver(
            startFocus: { snapshot in
                let selection = try selectionLoader(stage: "start_focus").selection()
                AppLogger.shared.record("focus_schedule_attempted", category: .monitoring, outcome: "attempted",
                    metadata: ["activity": MonitoringRuntime.focusName(snapshot.id), "limitMinutes": "\(snapshot.usageLimitMinutes)"])
                do {
                    try activity.startMonitoring(selection: selection, snapshot: snapshot)
                    AppLogger.shared.record("focus_schedule_completed", category: .monitoring, outcome: "succeeded", metadata: ["activity": MonitoringRuntime.focusName(snapshot.id)])
                } catch {
                    AppLogger.shared.failure("focus_schedule_failed", error: error, category: .monitoring, metadata: ["activity": MonitoringRuntime.focusName(snapshot.id), "originalErrorCode": "\((error as NSError).code)", "originalErrorDomain": (error as NSError).domain])
                    throw error
                }
            },
            startDeadline: { name, end in
                AppLogger.shared.record("deadline_schedule_attempted", category: .monitoring, outcome: "attempted", metadata: ["activity": name, "endsAt": end.ISO8601Format()])
                do {
                    try activity.startDeadline(name: name, end: end)
                    AppLogger.shared.record("deadline_schedule_completed", category: .monitoring, outcome: "succeeded", metadata: ["activity": name, "endsAt": end.ISO8601Format()])
                } catch {
                    AppLogger.shared.failure("deadline_schedule_failed", error: error, category: .monitoring, metadata: ["activity": name, "originalErrorCode": "\((error as NSError).code)", "originalErrorDomain": (error as NSError).domain])
                    throw error
                }
            },
            stop: { names in
                for name in names { AppLogger.shared.record("monitoring_stop_attempted", category: .monitoring, outcome: "attempted", metadata: ["activity": name]) }
                activity.stopActivities(names)
            },
            prepareShield: { try selectionLoader(stage: "prepare_shield").prepare() },
            clearShield: { settings.unblock() },
            activities: { activity.activityNames }),
            configuration: { storage.loadCycleConfiguration() },
            log: { event, detail, metadata in
                let failed = event.contains("failed") || event.contains("interrupted")
                AppLogger.shared.record(event, level: failed ? .error : (event.contains("rejected") ? .warning : .info),
                    category: .monitoring, metadata: metadata)
            }, operation: { action, work in try AppLogger.shared.withOperation(action, work) })
    }
}
