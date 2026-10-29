import Foundation
import DeviceActivity
import FamilyControls

protocol DeviceActivityServiceProtocol {
    func startMonitoring(selection: FamilyActivitySelection, snapshot: CycleSnapshot) throws
    func startDeadline(name: String, end: Date) throws
    func stopActivities(_ names: [String])
    var activityNames: [String] { get }
    func stopMonitoring()
}

final class DeviceActivityService: DeviceActivityServiceProtocol {
    private let center = DeviceActivityCenter()
    var activityNames: [String] {
        AppLogger.shared.timed("device_inventory") { center.activities.map(\.rawValue) }
    }

    static func makeDailySchedule() -> DeviceActivitySchedule {
        DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0),
                               intervalEnd: DateComponents(hour: 23, minute: 59), repeats: true)
    }

    static func checkpointStep(for limitMinutes: Int) -> Int {
        CheckpointCalculator.checkpointStep(for: limitMinutes)
    }

    static func makeFocusEvents(selection: FamilyActivitySelection, limitMinutes: Int)
        -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minute in CheckpointCalculator.generateCheckpoints(for: limitMinutes) {
            events[DeviceActivityConstants.checkpointEvent(minute: minute)] = DeviceActivityEvent(
                applications: selection.applicationTokens, categories: selection.categoryTokens,
                webDomains: [], threshold: DateComponents(minute: minute), includesPastActivity: false)
        }
        events[DeviceActivityConstants.thresholdEvent] = DeviceActivityEvent(
            applications: selection.applicationTokens, categories: selection.categoryTokens,
            webDomains: [], threshold: DateComponents(minute: limitMinutes), includesPastActivity: false)
        return events
    }

    static func deadlineSchedule(end: Date, now: Date = Date()) throws -> DeviceActivitySchedule {
        // Use complete dates in UTC so midnight, DST and device time-zone changes cannot
        // silently choose a different wall-clock day. Validate Apple's actual interpretation.
        let plan = try DeadlineSchedulePlan(end: end, now: now)
        let schedule = DeviceActivitySchedule(intervalStart: plan.startComponents,
                                             intervalEnd: plan.endComponents, repeats: false)
        try plan.validate(schedule.nextInterval)
        return schedule
    }

    func startDeadline(name: String, end: Date) throws {
        let schedule = try Self.deadlineSchedule(end: end)
        try AppLogger.shared.timed("device_start", metadata: ["activity": name]) {
            try center.startMonitoring(DeviceActivityName(name), during: schedule)
        }
    }

    func startMonitoring(selection: FamilyActivitySelection, snapshot: CycleSnapshot) throws {
        let schedule = Self.makeDailySchedule()
        guard schedule.nextInterval != nil else { throw LifecycleError.invalidSchedule }
        try AppLogger.shared.timed("device_start", metadata: ["activity": MonitoringRuntime.focusName(snapshot.id)]) {
            try center.startMonitoring(DeviceActivityName(MonitoringRuntime.focusName(snapshot.id)), during: schedule,
                events: Self.makeFocusEvents(selection: selection, limitMinutes: snapshot.usageLimitMinutes))
        }
    }

    func stopActivities(_ names: [String]) {
        guard !names.isEmpty else { return }
        AppLogger.shared.timed("device_stop", metadata: ["activityCount": "\(names.count)"]) {
            center.stopMonitoring(names.map { DeviceActivityName($0) })
        }
    }
    func stopMonitoring() { stopActivities(activityNames.filter { $0.hasPrefix("breakloop.") }) }
}
