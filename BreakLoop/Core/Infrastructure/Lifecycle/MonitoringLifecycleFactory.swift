import Foundation
import FamilyControls

extension MonitoringLifecycle {
    static func make(storage: AppGroupStorage,
                     activity: DeviceActivityServiceProtocol = DeviceActivityService(),
                     settings: ManagedSettingsServiceProtocol = ManagedSettingsService()) -> MonitoringLifecycle {
        let selectionLoader = ShieldSelectionLoader(
            load: { try storage.loadActivitySelection() },
            supported: {
                ShieldSelectionSupport.isSupported(applications: $0.applicationTokens.count,
                    categories: $0.categoryTokens.count, webDomains: $0.webDomainTokens.count)
            },
            apply: { settings.block($0) })
        return MonitoringLifecycle(storage: storage, driver: MonitoringDriver(
            startFocus: { snapshot in
                let selection = try selectionLoader.selection()
                try activity.startMonitoring(selection: selection, snapshot: snapshot)
            },
            startDeadline: { try activity.startDeadline(name: $0, end: $1) },
            stop: { activity.stopActivities($0) },
            prepareShield: { try selectionLoader.prepare() },
            clearShield: { settings.unblock() },
            activities: { activity.activityNames }),
            configuration: { storage.loadCycleConfiguration() },
            log: { event, detail, metadata in
                AppLogger.shared.warning(event, message: detail, category: .monitoring,
                                         metadata: metadata.merging(["activityOrError": detail, "event": event]) { existing, _ in existing })
            })
    }
}
