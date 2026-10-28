import Foundation
import DeviceActivity

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let storage = AppGroupStorage()
    private var lifecycle: MonitoringLifecycle { .make(storage: storage) }

    private func perform(_ action: () throws -> Void) {
        // The runtime operation releases its lock before this bounded drain. Never wait
        // indefinitely for logging when iOS may end the extension process after its callback.
        defer { _ = PersistentLogStore.shared.flush(timeout: 0.05) }
        do { try action() } catch {
            AppLogger.shared.failure("monitor_callback_failed", error: error, category: .monitoring)
        }
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        perform { try lifecycle.intervalStarted(name: activity.rawValue) }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        perform { try lifecycle.intervalEnded(name: activity.rawValue) }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        if event == DeviceActivityConstants.thresholdEvent {
            perform { try lifecycle.threshold(name: activity.rawValue, minute: nil) }
        } else if let minute = DeviceActivityConstants.checkpointMinute(from: event) {
            perform { try lifecycle.threshold(name: activity.rawValue, minute: minute) }
        }
    }
}
