import Foundation
import FamilyControls

extension MonitoringLifecycle {
    static func make(storage: AppGroupStorage,
                     activity: DeviceActivityServiceProtocol = DeviceActivityService(),
                     settings: ManagedSettingsServiceProtocol = ManagedSettingsService()) -> MonitoringLifecycle {
        MonitoringLifecycle(storage: storage, driver: MonitoringDriver(
            startFocus: { snapshot in
                guard let selection = try storage.loadActivitySelection() else { throw LifecycleError.storageUnavailable }
                try activity.startMonitoring(selection: selection, snapshot: snapshot)
            },
            startDeadline: { try activity.startDeadline(name: $0, end: $1) },
            stop: { activity.stopActivities($0) },
            shield: { blocked in
                if blocked {
                    if let selection = try? storage.loadActivitySelection() { settings.block(selection) }
                } else { settings.unblock() }
            },
            activities: { activity.activityNames }),
            configuration: { storage.loadCycleConfiguration() },
            log: { event, detail in
                AppLogger.shared.warning(event, message: detail, category: .monitoring,
                                         metadata: ["activityOrError": detail])
            })
    }
}
