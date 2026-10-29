import Foundation
import DeviceActivity

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let storage = AppGroupStorage()
    private var lifecycle: MonitoringLifecycle { .make(storage: storage) }

    private func perform(kind: String, activity: String, _ action: () throws -> Void) {
        let span = AppLogger.shared.timingBegin("device_callback", metadata: ["phase": kind, "activity": activity])
        // The runtime operation releases its lock before this bounded drain. Never wait
        // indefinitely for logging when iOS may end the extension process after its callback.
        defer {
            AppLogger.shared.timingEnd("device_callback", span: span, metadata: ["phase": kind, "activity": activity])
            _ = PersistentLogStore.shared.flush(timeout: 0.05)
        }
        do { try action() } catch {
            AppLogger.shared.failure("monitor_callback_failed", error: error, category: .monitoring)
        }
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        perform(kind: "interval_start", activity: activity.rawValue) {
            super.intervalDidStart(for: activity)
            try lifecycle.intervalStarted(name: activity.rawValue)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        perform(kind: "interval_end", activity: activity.rawValue) {
            super.intervalDidEnd(for: activity)
            try lifecycle.intervalEnded(name: activity.rawValue)
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        perform(kind: "threshold", activity: activity.rawValue) {
            super.eventDidReachThreshold(event, activity: activity)
            if event == DeviceActivityConstants.thresholdEvent {
                try lifecycle.threshold(name: activity.rawValue, minute: nil)
            } else if let minute = DeviceActivityConstants.checkpointMinute(from: event) {
                try lifecycle.threshold(name: activity.rawValue, minute: minute)
            }
        }
    }
}
