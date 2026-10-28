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
                try activity.startMonitoring(selection: selection, snapshot: snapshot)
            },
            startDeadline: { try activity.startDeadline(name: $0, end: $1) },
            stop: { activity.stopActivities($0) },
            prepareShield: { try selectionLoader(stage: "prepare_shield").prepare() },
            clearShield: { settings.unblock() },
            activities: { activity.activityNames }),
            configuration: { storage.loadCycleConfiguration() },
            log: { event, detail, metadata in
                AppLogger.shared.warning(event, message: detail, category: .monitoring,
                                         metadata: metadata.merging(["activityOrError": detail, "event": event]) { existing, _ in existing })
            })
    }
}
