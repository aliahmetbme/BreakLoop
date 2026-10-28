import Foundation

// One atomic runtime record; configuration and the user's selection remain in their existing keys.
struct MonitoringRuntime: Codable, Equatable {
    var snapshot: CycleSnapshot?
    var checkpoint: UsageCheckpointState?
    var cooldown: RestrictionDeadline?
    var deepFocus: DeepFocusSession?
    var legacyCooldown: Bool?
    var legacyDeepFocus: Bool?
    var cooldownName: String? { cooldown.map { legacyCooldown == true ? "breakloop.cooldown" : Self.cooldownName($0.id) } }
    var deepFocusName: String? { deepFocus.map { legacyDeepFocus == true ? "breakloop.deepFocus" : Self.deepFocusName($0.id) } }

    var activityNames: [String] {
        [snapshot.map { Self.focusName($0.id) }, cooldownName, deepFocusName].compactMap { $0 }
    }
    static func focusName(_ id: UUID) -> String { "breakloop.focus.\(id.uuidString)" }
    static func cooldownName(_ id: UUID) -> String { "breakloop.cooldown.\(id.uuidString)" }
    static func deepFocusName(_ id: UUID) -> String { "breakloop.deepFocus.\(id.uuidString)" }
    func ownsShield(at now: Date) -> Bool {
        (cooldown.map { $0.endsAt > now } ?? false) || (deepFocus.map { $0.endsAt > now } ?? false)
    }
}

struct RestrictionDeadline: Codable, Equatable {
    let id: UUID
    let endsAt: Date
    init(id: UUID = UUID(), endsAt: Date) { self.id = id; self.endsAt = endsAt }
}

protocol MonitoringRuntimeStore {
    // Must serialize *across processes*, including the entire schedule/commit/shield operation.
    func withRuntimeLock<T>(_ body: () throws -> T) throws -> T
    func readRuntime() throws -> MonitoringRuntime
    func writeRuntime(_ state: MonitoringRuntime) throws
}

struct MonitoringDriver {
    var startFocus: (CycleSnapshot) throws -> Void
    var startDeadline: (_ name: String, _ end: Date) throws -> Void
    var stop: ([String]) -> Void
    var shield: (Bool) -> Void
    var activities: () -> [String]
}

// Shared by app and extension, and exercised directly by regression tests.
final class MonitoringLifecycle {
    private let storage: any MonitoringRuntimeStore
    private let driver: MonitoringDriver
    private let now: () -> Date
    private let configuration: () -> CycleConfiguration
    private let log: (String, String) -> Void

    init(storage: any MonitoringRuntimeStore, driver: MonitoringDriver,
         now: @escaping () -> Date = Date.init,
         configuration: @escaping () -> CycleConfiguration,
         log: @escaping (String, String) -> Void = { _, _ in }) {
        self.storage = storage; self.driver = driver; self.now = now
        self.configuration = configuration; self.log = log
    }

    // Schedule unique generation first while callbacks wait on the shared lock. Publish atomically
    // only after success. A failed write stops only the uncommitted generation, preserving the old one.
    private func commit(_ next: MonitoringRuntime, replacing old: MonitoringRuntime,
                        start: () throws -> Void = {}) throws {
        let added = next.activityNames.filter { !old.activityNames.contains($0) }
        do {
            try start()
            try storage.writeRuntime(next)
        } catch {
            driver.stop(added)
            log("transition_failed", String(describing: error))
            throw error
        }
        driver.stop(driver.activities().filter { $0.hasPrefix("breakloop.") && !next.activityNames.contains($0) })
        driver.shield(next.ownsShield(at: now()))
    }

    func start() throws {
        try storage.withRuntimeLock {
            let old = try storage.readRuntime()
            guard old.snapshot == nil else { return } // Repeated Start must preserve a valid session.
            var next = old
            let snapshot = CycleSnapshot(configuration: configuration(), startedAt: now())
            next.snapshot = snapshot; next.checkpoint = nil
            try commit(next, replacing: old) { try driver.startFocus(snapshot) }
        }
    }

    func stop(all: Bool = false) throws {
        try storage.withRuntimeLock {
            let old = try storage.readRuntime()
            var next = old
            next.snapshot = nil; next.checkpoint = nil; next.cooldown = nil
            if all { next.deepFocus = nil }
            try commit(next, replacing: old)
        }
    }

    func startDeepFocus(minutes: Int) throws {
        try storage.withRuntimeLock {
            let old = try storage.readRuntime()
            guard minutes >= 15, minutes <= 24 * 60 else { throw LifecycleError.invalidDuration }
            var next = old
            let session = DeepFocusSession(startedAt: Date(timeIntervalSince1970: ceil(now().timeIntervalSince1970)), durationMinutes: minutes)
            next.deepFocus = session; next.legacyDeepFocus = nil
            try commit(next, replacing: old) {
                try driver.startDeadline(MonitoringRuntime.deepFocusName(session.id), session.endsAt)
            }
        }
    }

    func stopDeepFocus() throws {
        try storage.withRuntimeLock {
            let old = try storage.readRuntime()
            var next = old; next.deepFocus = nil
            try commit(next, replacing: old)
        }
    }

    func extendCooldown(minutes: Int) throws {
        try storage.withRuntimeLock {
            let old = try storage.readRuntime()
            guard minutes > 0, let end = old.cooldown?.endsAt, end > now() else { return }
            var next = old
            let deadline = RestrictionDeadline(endsAt: Date(timeIntervalSince1970: ceil(end.timeIntervalSince1970 + Double(minutes) * 60)))
            next.cooldown = deadline; next.legacyCooldown = nil
            try commit(next, replacing: old) {
                try driver.startDeadline(MonitoringRuntime.cooldownName(deadline.id), deadline.endsAt)
            }
        }
    }

    func intervalEnded(name: String) throws {
        try storage.withRuntimeLock {
            let state = try storage.readRuntime()
            let valid = state.cooldown.map { state.cooldownName == name && $0.endsAt <= now() } == true
                || state.deepFocus.map { state.deepFocusName == name && $0.endsAt <= now() } == true
            guard valid else { log("stale_interval_rejected", name); return }
            try reconcileLocked(state)
        }
    }

    func intervalStarted(name: String) throws {
        try storage.withRuntimeLock {
            let state = try storage.readRuntime()
            guard state.activityNames.contains(name) else { log("stale_start_rejected", name); return }
            try reconcileLocked(state)
        }
    }

    func reconcile() throws {
        try storage.withRuntimeLock { try reconcileLocked(storage.readRuntime()) }
    }

    private func reconcileLocked(_ old: MonitoringRuntime) throws {
        var next = old
        let cooldownExpired = next.cooldown.map { $0.endsAt <= now() } ?? false
        if cooldownExpired { next.cooldown = nil; next.checkpoint = nil }
        if next.deepFocus.map({ $0.endsAt <= now() }) == true { next.deepFocus = nil }
        // A completed cooldown earns a fresh shared usage budget. Deep Focus never owns that budget.
        if cooldownExpired, next.snapshot != nil {
            next.snapshot = CycleSnapshot(configuration: configuration(), startedAt: now())
        }
        let currentNames = driver.activities()
        let snapshotToStart = next.snapshot.flatMap { snapshot in
            (cooldownExpired || !currentNames.contains(MonitoringRuntime.focusName(snapshot.id))) ? snapshot : nil
        }
        // Persist expiration even if a fresh focus schedule fails, so a missed callback cannot strand a shield.
        do {
            try commit(next, replacing: old) {
                if let snapshotToStart { try driver.startFocus(snapshotToStart) }
            }
        } catch {
            if snapshotToStart != nil || cooldownExpired || next.deepFocus != old.deepFocus {
                next.snapshot = nil; next.checkpoint = nil
                try commit(next, replacing: old)
            }
            throw error
        }
    }

    func threshold(name: String, minute: Int?) throws {
        try storage.withRuntimeLock {
            let old = try storage.readRuntime()
            guard let snapshot = old.snapshot, name == MonitoringRuntime.focusName(snapshot.id),
                  old.cooldown == nil else { log("stale_threshold_rejected", name); return }
            let usage = minute ?? snapshot.usageLimitMinutes
            guard usage > 0, usage <= snapshot.usageLimitMinutes,
                  old.checkpoint.map({ usage > $0.usageMinute }) ?? true else {
                log("stale_checkpoint_rejected", name); return
            }
            var next = old
            let naturalRest = old.checkpoint.map {
                NaturalRestCalculator.calculate(currentUsageMinute: usage, currentTimestamp: now(),
                    previousUsageMinute: $0.usageMinute, previousTimestamp: $0.timestamp,
                    requiredRestMinutes: snapshot.restDurationMinutes).isNaturalRest
            } ?? false
            if naturalRest {
                let fresh = CycleSnapshot(configuration: configuration(), startedAt: now())
                next.snapshot = fresh; next.checkpoint = nil
                try commit(next, replacing: old) { try driver.startFocus(fresh) }
            } else if minute == nil {
                let deadline = RestrictionDeadline(endsAt: Date(timeIntervalSince1970: ceil(now().timeIntervalSince1970 + Double(snapshot.restDurationMinutes) * 60)))
                next.cooldown = deadline; next.legacyCooldown = nil; next.checkpoint = nil
                try commit(next, replacing: old) {
                    try driver.startDeadline(MonitoringRuntime.cooldownName(deadline.id), deadline.endsAt)
                }
            } else {
                next.checkpoint = UsageCheckpointState(usageMinute: usage, timestamp: now())
                try storage.writeRuntime(next)
            }
        }
    }
}

enum LifecycleError: LocalizedError {
    case invalidDuration, invalidSchedule, storageUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidDuration: return "The monitoring duration is not supported."
        case .invalidSchedule: return "The system could not schedule the requested monitoring interval."
        case .storageUnavailable: return "Shared monitoring storage is unavailable."
        }
    }
}


struct DeadlineSchedulePlan {
    let start: Date
    let end: Date
    let startComponents: DateComponents
    let endComponents: DateComponents

    init(end: Date, now: Date) throws {
        let duration = end.timeIntervalSince(now)
        guard duration >= 15 * 60 - 1, duration <= 24 * 60 * 60 else { throw LifecycleError.invalidDuration }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func components(_ date: Date) -> DateComponents {
            var result = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            result.calendar = calendar; result.timeZone = calendar.timeZone
            return result
        }
        start = now; self.end = end
        startComponents = components(now); endComponents = components(end)
    }

    func validate(_ interval: DateInterval?) throws {
        guard let interval,
              abs(interval.start.timeIntervalSince(start)) < 2,
              abs(interval.end.timeIntervalSince(end)) < 0.01,
              abs(interval.duration - end.timeIntervalSince(start)) < 2 else { throw LifecycleError.invalidSchedule }
    }
}
