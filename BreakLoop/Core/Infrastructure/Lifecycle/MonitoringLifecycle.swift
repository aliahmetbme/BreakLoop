import Foundation
import Darwin

// One atomic runtime record; configuration and the user's selection remain in their existing keys.
struct MonitoringRuntime: Codable, Equatable {
    var pendingTransition: PendingMonitoringTransition?
    var retiredActivities: [String]?
    var deferredCallbacks: [DeferredMonitoringCallback]?
    var snapshot: CycleSnapshot?
    var checkpoint: UsageCheckpointState?
    var cooldown: RestrictionDeadline?
    var deepFocus: DeepFocusSession?
    var legacyCooldown: Bool?
    var legacyDeepFocus: Bool?
    var legacyFocus: Bool?
    var attention: MonitoringAttention?
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
    // Serialize short state/ownership critical sections across processes. Apple DeviceActivity
    // calls must use withoutRuntimeLock and revalidate their durable intent on return.
    func withRuntimeLock<T>(_ body: () throws -> T) throws -> T
    func withoutRuntimeLock<T>(_ body: () throws -> T) throws -> T
    func readRuntime() throws -> MonitoringRuntime
    func writeRuntime(_ state: MonitoringRuntime) throws
}

struct MonitoringDriver {
    var startFocus: (CycleSnapshot) throws -> Void
    var startDeadline: (_ name: String, _ end: Date) throws -> Void
    var stop: ([String]) -> Void
    // Preparation may fail; the returned captured-selection write cannot throw after publication.
    var prepareShield: () throws -> () -> Void
    var clearShield: () -> Void
    var activities: () -> [String]
}

struct DeferredMonitoringCallback: Codable, Equatable {
    enum Kind: String, Codable { case started, ended, threshold }
    let kind: Kind
    let name: String
    var minute: Int? = nil
}

struct PendingMonitoringTransition: Codable, Equatable {
    let id: UUID
    let ownerPID: Int32
    let ownerInstance: UUID
    let addedActivities: [String]
    var callbacks: [DeferredMonitoringCallback]?
    init(addedActivities: [String]) {
        id = UUID(); ownerPID = getpid(); ownerInstance = PendingMonitoringOperations.instance
        self.addedActivities = addedActivities
    }
}

// Process-local liveness is not a timeout lease. Cross-process death is checked via
// kill(pid, 0); EPERM means possibly alive, never permission to cancel an active intent.
private enum PendingMonitoringOperations {
    static let instance = UUID()
    static let lock = NSLock()
    static var active: Set<UUID> = []
    static func begin(_ id: UUID) { lock.lock(); defer { lock.unlock() }; active.insert(id) }
    static func end(_ id: UUID) { lock.lock(); defer { lock.unlock() }; active.remove(id) }
    static func isActive(_ pending: PendingMonitoringTransition) -> Bool {
        if pending.ownerPID == getpid() {
            lock.lock(); defer { lock.unlock() }
            return pending.ownerInstance == instance && active.contains(pending.id)
        }
        return kill(pending.ownerPID, 0) == 0 || errno != ESRCH
    }
}

// Shared by app and extension, and exercised directly by regression tests.
final class MonitoringLifecycle {
    private let storage: any MonitoringRuntimeStore
    private let driver: MonitoringDriver
    private let now: () -> Date
    private let configuration: () -> CycleConfiguration
    private let operation: (String, () throws -> Void) throws -> Void
    private let logger: (String, String, [String: String]) -> Void

    init(storage: any MonitoringRuntimeStore, driver: MonitoringDriver,
         now: @escaping () -> Date = Date.init,
         configuration: @escaping () -> CycleConfiguration,
         log: @escaping (String, String, [String: String]) -> Void = { _, _, _ in },
         operation: @escaping (String, () throws -> Void) throws -> Void = { _, work in try work() }) {
        self.storage = storage; self.driver = driver; self.now = now
        self.configuration = configuration; self.logger = log; self.operation = operation
    }

    private func withOperationLock(_ action: String, callback: DeferredMonitoringCallback? = nil,
                                   _ work: () throws -> Void) throws {
        do {
        try operation(action) {
            try storage.withRuntimeLock {
                var state = try storage.readRuntime()
                if let pending = state.pendingTransition {
                    if PendingMonitoringOperations.isActive(pending) {
                        if let callback {
                            var callbacks = pending.callbacks ?? []
                            if !callbacks.contains(callback) { callbacks.append(callback) }
                            state.pendingTransition?.callbacks = callbacks
                            try storage.writeRuntime(state)
                            report("transition_callback_deferred", action)
                            return
                        }
                        if action == "reconcile" { return }
                        guard action == "stop_breakloop" || action == "stop_deep_focus" else {
                            throw LifecycleError.transitionInProgress
                        }
                    }
                    if !PendingMonitoringOperations.isActive(pending), let callback,
                       callback.kind == .threshold {
                        let actual = try storage.withoutRuntimeLock { driver.activities() }
                        if !actual.contains(callback.name) {
                            report("stale_threshold_rejected", callback.name)
                            return
                        }
                        // Re-read after the inventory boundary rather than overwrite a newer intent.
                        guard try storage.readRuntime() == state else { throw LifecycleError.transitionCancelled }
                    }
                    // Cancellation/recovery invalidates the intent before any stop call.
                    // Completion of its in-flight Apple request can no longer publish it.
                    state.pendingTransition = nil
                    state.retiredActivities = unique((state.retiredActivities ?? []) + pending.addedActivities)
                    state.deferredCallbacks = uniqueCallbacks((state.deferredCallbacks ?? []) + (pending.callbacks ?? []))
                    try storage.writeRuntime(state)
                    report("transition_recovered", action, metadata: ["spanId": pending.id.uuidString])
                }
                try work()
            }
        }
        } catch {
            try? drainCallbacks()
            throw error
        }
        try drainCallbacks()
    }

    private func unique(_ values: [String]) -> [String]? {
        let result = Array(Set(values)).sorted()
        return result.isEmpty ? nil : result
    }
    private func uniqueCallbacks(_ values: [DeferredMonitoringCallback]) -> [DeferredMonitoringCallback]? {
        var result: [DeferredMonitoringCallback] = []
        for value in values where !result.contains(value) { result.append(value) }
        return result.isEmpty ? nil : result
    }

    private func drainCallbacks() throws {
        let key = "breakloop.runtime.drainingCallbacks"
        guard Thread.current.threadDictionary[key] == nil else { return }
        Thread.current.threadDictionary[key] = true
        defer { Thread.current.threadDictionary.removeObject(forKey: key) }
        while true {
            let callback = try storage.withRuntimeLock {
                let state = try storage.readRuntime()
                return state.pendingTransition == nil ? state.deferredCallbacks?.first : nil
            }
            guard let callback else { return }
            // Keep the event durable until replay succeeds. A process death can replay it
            // again; generation checks and checkpoint monotonicity make that idempotent.
            switch callback.kind {
            case .started: try intervalStarted(name: callback.name)
            case .ended: try intervalEnded(name: callback.name)
            case .threshold: try threshold(name: callback.name, minute: callback.minute)
            }
            try storage.withRuntimeLock {
                var state = try storage.readRuntime()
                state.deferredCallbacks = uniqueCallbacks((state.deferredCallbacks ?? []).filter { $0 != callback })
                try storage.writeRuntime(state)
            }
        }
    }

    // Inventory is also an XPC boundary. Never use a pre-inventory state after another
    // process changed it while this lease was released.
    private func inventory() throws -> [String] {
        let before = try storage.readRuntime()
        let names = try storage.withoutRuntimeLock { driver.activities() }
        guard try storage.readRuntime() == before else { throw LifecycleError.transitionCancelled }
        return names
    }

    private func stopActivities(_ names: [String]) throws {
        guard !names.isEmpty else { return }
        try storage.withoutRuntimeLock { driver.stop(names) }
    }

    private func report(_ event: String, _ detail: String, metadata: [String: String] = [:]) {
        logger(event, detail, metadata)
    }

    // Preparation and scheduling can fail before publication. ManagedSettings writes after
    // publication use the already validated/captured selection and have no throwing API.
    private func commit(_ proposed: MonitoringRuntime, replacing old: MonitoringRuntime,
                        clearsSelectionAttentionOnStart: Bool = false, schedules: Bool = false,
                        start: () throws -> Void = {}) throws {
        var next = proposed
        let live = try storage.readRuntime()
        if !schedules {
            guard live.snapshot?.id == old.snapshot?.id, live.cooldown == old.cooldown,
                  live.deepFocus == old.deepFocus, live.pendingTransition == nil else {
                throw LifecycleError.transitionCancelled
            }
            next.deferredCallbacks = uniqueCallbacks((next.deferredCallbacks ?? []) + (live.deferredCallbacks ?? []))
            next.retiredActivities = unique((next.retiredActivities ?? []) + (live.retiredActivities ?? []))
        }
        let apply: () -> Void
        do { apply = next.ownsShield(at: now()) ? try driver.prepareShield() : driver.clearShield }
        catch { try recordSelectionFailure(error, state: old); throw error }
        if next.ownsShield(at: now()), next.attention?.code.isSelectionFailure == true, next.attention?.resolvedAt == nil {
            next.attention?.resolvedAt = now()
        }
        let added = next.activityNames.filter { !old.activityNames.contains($0) }
        let intent = PendingMonitoringTransition(addedActivities: added)
        if schedules {
            var reserved = old
            reserved.pendingTransition = intent
            PendingMonitoringOperations.begin(intent.id)
            do { try storage.writeRuntime(reserved) }
            catch { PendingMonitoringOperations.end(intent.id); throw error }
        }
        defer { if schedules { PendingMonitoringOperations.end(intent.id) } }
        do {
            if schedules {
                try storage.withoutRuntimeLock { try start() }
                let current = try storage.readRuntime()
                guard current.pendingTransition?.id == intent.id else { throw LifecycleError.transitionCancelled }
                next.deferredCallbacks = uniqueCallbacks((current.deferredCallbacks ?? []) + (current.pendingTransition?.callbacks ?? []))
                next.retiredActivities = current.retiredActivities
                next.pendingTransition = nil
            }
            if clearsSelectionAttentionOnStart, next.attention?.code.isSelectionFailure == true { next.attention = nil }
            next.retiredActivities = unique((next.retiredActivities ?? []) + old.activityNames.filter { !next.activityNames.contains($0) })
            try storage.writeRuntime(next)
        } catch {
            // Roll back only this intent. A concurrent Stop or newer generation wins.
            var current = try storage.readRuntime()
            if current.pendingTransition?.id == intent.id {
                let callbacks = current.pendingTransition?.callbacks ?? []
                current.pendingTransition = nil
                current.deferredCallbacks = uniqueCallbacks((current.deferredCallbacks ?? []) + callbacks)
                current.retiredActivities = unique((current.retiredActivities ?? []) + added)
                do { try storage.writeRuntime(current) }
                catch { report("transition_rollback_pending", "Recovery remains durable.") }
            }
            let protected = Set(current.activityNames + (current.pendingTransition?.addedActivities ?? []))
            try stopActivities(added.filter { !protected.contains($0) })
            // Prune a successfully stopped rollback ledger without restoring old state.
            var cleaned = try storage.readRuntime()
            cleaned.retiredActivities = unique((cleaned.retiredActivities ?? []).filter { !added.contains($0) })
            try? storage.writeRuntime(cleaned)
            report("transition_failed", String(describing: error))
            throw error
        }
        // Shield ownership is serialized with publication. No stale shield write after
        // releasing for stop/inventory; cleanup re-reads the current generation instead.
        if next.ownsShield(at: now()) { apply() } else { driver.clearShield() }
        do { try stopObsolete() }
        catch { report("monitoring_cleanup_failed", String(describing: error)) }
    }

    private func stopObsolete() throws {
        let names = try storage.withoutRuntimeLock { driver.activities() }
        var current = try storage.readRuntime()
        let protected = Set(current.activityNames + (current.pendingTransition?.addedActivities ?? []))
        let obsolete = Array(Set(names.filter { $0.hasPrefix("breakloop.") && !protected.contains($0) }
            + (current.retiredActivities ?? []).filter { !protected.contains($0) })).sorted()
        guard !obsolete.isEmpty else { return }
        current.retiredActivities = unique((current.retiredActivities ?? []) + obsolete)
        try storage.writeRuntime(current)
        try stopActivities(obsolete)
        var after = try storage.readRuntime()
        after.retiredActivities = unique((after.retiredActivities ?? []).filter { !obsolete.contains($0) })
        try storage.writeRuntime(after)
    }

    private func recordSelectionFailure(_ error: Error, state: MonitoringRuntime) throws {
        var next = state
        next.attention = MonitoringAttention(code: SelectionFailure.classify(error),
            occurredAt: now(), activity: state.cooldownName ?? state.deepFocusName,
            message: error.localizedDescription)
        report("shield_selection_failed", next.attention!.diagnostic,
               metadata: ["failureCode": next.attention!.code.rawValue, "activity": next.attention!.activity ?? "none"])
        do { try storage.writeRuntime(next) } catch let persistenceError {
            report("attention_persistence_failed", String(describing: persistenceError))
            throw MonitoringRecoveryError(original: error, persistence: persistenceError)
        }
    }

    // The normal generation has spent its budget but has no release schedule. Invalidate it
    // before stopping it. If storage fails, stop it anyway and reject callbacks by inventory;
    // foreground reconciliation must not automatically revive a missing generation.
    private func interrupt(_ old: MonitoringRuntime, error: Error, code: MonitoringFailureCode) throws {
        let current = try storage.readRuntime()
        guard current.snapshot?.id == old.snapshot?.id, current.cooldown == old.cooldown else {
            throw LifecycleError.transitionCancelled
        }
        var interrupted = current
        interrupted.snapshot = nil; interrupted.checkpoint = nil
        interrupted.attention = MonitoringAttention(code: code, occurredAt: now(),
            activity: old.snapshot.map { MonitoringRuntime.focusName($0.id) },
            message: "BreakLoop monitoring was interrupted. \(error.localizedDescription) Fix the problem and start BreakLoop again.")
        report("normal_cycle_interrupted", interrupted.attention!.diagnostic,
               metadata: ["failureCode": code.rawValue, "activity": interrupted.attention!.activity ?? "none",
                          "originalErrorDomain": (error as NSError).domain, "originalErrorCode": "\((error as NSError).code)"])
        do { try storage.writeRuntime(interrupted) } catch let persistenceError {
            if let snapshot = old.snapshot { try stopActivities([MonitoringRuntime.focusName(snapshot.id)]) }
            report("interruption_persistence_failed", "original=\(error); persistence=\(persistenceError)",
                   metadata: ["failureCode": MonitoringFailureCode.runtimePersistence.rawValue,
                              "activity": interrupted.attention!.activity ?? "none",
                              "originalFailureCode": code.rawValue, "safeStatePersisted": "false"])
            throw MonitoringRecoveryError(original: error, persistence: persistenceError)
        }
        try stopObsolete()
        // Preserve an existing Deep Focus shield without reloading a possibly broken selection.
        // No new shield is introduced by interruption, and expired/no owners can safely clear.
        if !(try storage.readRuntime()).ownsShield(at: now()) { driver.clearShield() }
        throw error
    }

    func start() throws {
        try withOperationLock("start_breakloop") {
            let old = try storage.readRuntime()
            if let snapshot = old.snapshot,
               try (old.legacyFocus == true || inventory().contains(MonitoringRuntime.focusName(snapshot.id))) {
                return // Repeated Start preserves a valid session; explicit Start can replace a missing generation.
            }
            var next = old
            let snapshot = CycleSnapshot(configuration: configuration(), startedAt: now())
            next.snapshot = snapshot; next.checkpoint = nil; next.legacyFocus = nil; next.attention = nil
            try commit(next, replacing: old, schedules: true) { try driver.startFocus(snapshot) }
        }
    }

    func stop(all: Bool = false) throws {
        try withOperationLock("stop_breakloop") {
            let old = try storage.readRuntime()
            var next = old
            next.snapshot = nil; next.checkpoint = nil; next.cooldown = nil
            if all { next.deepFocus = nil }
            try commit(next, replacing: old)
        }
    }

    func startDeepFocus(minutes: Int) throws {
        try withOperationLock("start_deep_focus") {
            let old = try storage.readRuntime()
            guard minutes >= 15, minutes <= 24 * 60 else { throw LifecycleError.invalidDuration }
            var next = old
            let session = DeepFocusSession(startedAt: Date(timeIntervalSince1970: ceil(now().timeIntervalSince1970)), durationMinutes: minutes)
            next.deepFocus = session; next.legacyDeepFocus = nil
            try commit(next, replacing: old, schedules: true) {
                try driver.startDeadline(MonitoringRuntime.deepFocusName(session.id), session.endsAt)
            }
        }
    }

    func stopDeepFocus() throws {
        try withOperationLock("stop_deep_focus") {
            let old = try storage.readRuntime()
            var next = old; next.deepFocus = nil
            try commit(next, replacing: old)
        }
    }

    func extendCooldown(minutes: Int) throws {
        try withOperationLock("extend_cooldown") {
            let old = try storage.readRuntime()
            guard minutes > 0, let end = old.cooldown?.endsAt, end > now() else { return }
            var next = old
            let deadline = RestrictionDeadline(endsAt: Date(timeIntervalSince1970: ceil(end.timeIntervalSince1970 + Double(minutes) * 60)))
            next.cooldown = deadline; next.legacyCooldown = nil
            try commit(next, replacing: old, schedules: true) {
                try driver.startDeadline(MonitoringRuntime.cooldownName(deadline.id), deadline.endsAt)
            }
        }
    }

    func intervalEnded(name: String) throws {
        try withOperationLock("interval_end_callback", callback: DeferredMonitoringCallback(kind: .ended, name: name)) {
            let state = try storage.readRuntime()
            let valid = state.cooldown.map { state.cooldownName == name && $0.endsAt <= now() } == true
                || state.deepFocus.map { state.deepFocusName == name && $0.endsAt <= now() } == true
            guard valid else { report("stale_interval_rejected", name); return }
            try reconcileLocked(state)
        }
    }

    func intervalStarted(name: String) throws {
        try withOperationLock("interval_start_callback", callback: DeferredMonitoringCallback(kind: .started, name: name)) {
            let state = try storage.readRuntime()
            guard state.activityNames.contains(name) else { report("stale_start_rejected", name); return }
            try reconcileLocked(state)
        }
    }

    func reconcile() throws {
        try withOperationLock("reconcile") { try reconcileLocked(storage.readRuntime()) }
    }

    private func reconcileLocked(_ old: MonitoringRuntime) throws {
        var next = old
        let cooldownExpired = next.cooldown.map { $0.endsAt <= now() } ?? false
        if cooldownExpired {
            report("cooldown_expired", "Cooldown deadline elapsed.", metadata: ["activity": old.cooldownName ?? "none"])
            next.cooldown = nil; next.checkpoint = nil
        }
        if next.deepFocus.map({ $0.endsAt <= now() }) == true {
            report("deep_focus_expired", "Deep Focus deadline elapsed.", metadata: ["activity": old.deepFocusName ?? "none"])
            next.deepFocus = nil
        }
        if cooldownExpired, next.snapshot != nil {
            next.snapshot = CycleSnapshot(configuration: configuration(), startedAt: now())
        }
        let currentNames = try inventory()
        if let snapshot = old.snapshot, !cooldownExpired, old.legacyFocus != true,
           !currentNames.contains(MonitoringRuntime.focusName(snapshot.id)) {
            // An absent monitor can be the result of an interruption whose write failed.
            // Never silently resurrect it; a user can explicitly start a fresh generation.
            try interrupt(next, error: LifecycleError.monitorUnavailable, code: .monitorUnavailable)
        }
        let snapshotToStart = next.snapshot.flatMap { snapshot in
            (cooldownExpired || !currentNames.contains(MonitoringRuntime.focusName(snapshot.id))) ? snapshot : nil
        }
        next.legacyFocus = nil
        do {
            report("focus_restart_evaluated", "Evaluating foreground/expiry focus restart.", metadata: [
                "cooldownExpired": "\(cooldownExpired)", "willStartFocus": "\(snapshotToStart != nil)",
                "priorAttentionCode": old.attention?.code.rawValue ?? "none",
                "priorAttentionAt": old.attention.map { "\($0.occurredAt.timeIntervalSince1970)" } ?? "none"])
            try commit(next, replacing: old, clearsSelectionAttentionOnStart: snapshotToStart != nil, schedules: snapshotToStart != nil) {
                if let snapshotToStart { try driver.startFocus(snapshotToStart) }
            }
        } catch {
            if error as? LifecycleError == .transitionCancelled { throw error }
            if SelectionFailure.isSelectionError(error) || (error as? MonitoringRecoveryError).map({ SelectionFailure.isSelectionError($0.original) }) == true {
                // Persist elapsed-owner cleanup even while another valid owner cannot be reapplied.
                // Do not clear that owner's already installed shield or schedule.
                if snapshotToStart != nil { next.snapshot = nil; next.checkpoint = nil }
                next.attention = MonitoringAttention(code: SelectionFailure.classify((error as? MonitoringRecoveryError)?.original ?? error),
                    occurredAt: now(), activity: next.cooldownName ?? next.deepFocusName,
                    message: error.localizedDescription)
                do { try storage.writeRuntime(next) } catch let persistenceError {
                    throw MonitoringRecoveryError(original: error, persistence: persistenceError)
                }
                try stopObsolete()
                if !(try storage.readRuntime()).ownsShield(at: now()) { driver.clearShield() }
            } else if snapshotToStart != nil || cooldownExpired || next.deepFocus != old.deepFocus {
                next.snapshot = nil; next.checkpoint = nil
                try commit(next, replacing: old)
            }
            throw error
        }
    }

    func threshold(name: String, minute: Int?) throws {
        try withOperationLock("threshold_callback", callback: DeferredMonitoringCallback(kind: .threshold, name: name, minute: minute)) {
            let old = try storage.readRuntime()
            guard let snapshot = old.snapshot, name == MonitoringRuntime.focusName(snapshot.id),
                  old.cooldown == nil, try inventory().contains(name) else { report("stale_threshold_rejected", name); return }
            let usage = minute ?? snapshot.usageLimitMinutes
            report(minute == nil ? "usage_threshold_reached" : "usage_checkpoint_reached", "Usage callback observed.",
                   metadata: ["usageMinute": "\(usage)", "activity": name])
            guard usage > 0, usage <= snapshot.usageLimitMinutes,
                  old.checkpoint.map({ usage > $0.usageMinute }) ?? true else {
                report("stale_checkpoint_rejected", name); return
            }
            var next = old
            let naturalRest = old.checkpoint.map {
                NaturalRestCalculator.calculate(currentUsageMinute: usage, currentTimestamp: now(),
                    previousUsageMinute: $0.usageMinute, previousTimestamp: $0.timestamp,
                    requiredRestMinutes: snapshot.restDurationMinutes).isNaturalRest
            } ?? false
            report("natural_rest_decided", "Natural rest evaluated.", metadata: ["naturalRest": "\(naturalRest)", "usageMinute": "\(usage)"])
            if naturalRest {
                let fresh = CycleSnapshot(configuration: configuration(), startedAt: now())
                next.snapshot = fresh; next.checkpoint = nil
                try commit(next, replacing: old, clearsSelectionAttentionOnStart: true, schedules: true) { try driver.startFocus(fresh) }
            } else if minute == nil {
                let deadline = RestrictionDeadline(endsAt: Date(timeIntervalSince1970: ceil(now().timeIntervalSince1970 + Double(snapshot.restDurationMinutes) * 60)))
                next.cooldown = deadline; next.legacyCooldown = nil; next.checkpoint = nil
                var phase: MonitoringFailureCode = .runtimePersistence
                do {
                    try commit(next, replacing: old, schedules: true) {
                        phase = .cooldownScheduling
                        try driver.startDeadline(MonitoringRuntime.cooldownName(deadline.id), deadline.endsAt)
                        phase = .runtimePersistence
                    }
                    report("cooldown_started", "Cooldown publication completed.", metadata: ["activity": MonitoringRuntime.cooldownName(deadline.id), "endsAt": deadline.endsAt.ISO8601Format()])
                } catch {
                    if error as? LifecycleError == .transitionCancelled { throw error }
                    let original = (error as? MonitoringRecoveryError)?.original ?? error
                    let code = SelectionFailure.isSelectionError(original) ? SelectionFailure.classify(original) : phase
                    try interrupt(old, error: error, code: code)
                }
            } else {
                next.checkpoint = UsageCheckpointState(usageMinute: usage, timestamp: now())
                try storage.writeRuntime(next)
            }
        }
    }
}

enum LifecycleError: LocalizedError, Equatable {
    case invalidDuration, invalidSchedule, storageUnavailable, monitorUnavailable, transitionInProgress, transitionCancelled
    var errorDescription: String? {
        switch self {
        case .transitionInProgress: return "A monitoring change is already in progress. Refresh status before trying again."
        case .transitionCancelled: return "The monitoring change was superseded. Refresh status before trying again."
        case .invalidDuration: return "The monitoring duration is not supported."
        case .invalidSchedule: return "The system could not schedule the requested monitoring interval."
        case .monitorUnavailable: return "The previous monitoring activity is no longer running. Start BreakLoop again."
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


// Optional additions to MonitoringRuntime keep existing JSON and legacy migration decodable.
enum MonitoringFailureCode: String, Codable {
    case selectionMissing, selectionCorrupted, selectionUnsupported, selectionUnavailable
    case cooldownScheduling, runtimePersistence, monitorUnavailable
    var isSelectionFailure: Bool {
        switch self {
        case .selectionMissing, .selectionCorrupted, .selectionUnsupported, .selectionUnavailable: return true
        default: return false
        }
    }
}

struct MonitoringAttention: Codable, Equatable {
    let code: MonitoringFailureCode
    let occurredAt: Date
    let activity: String?
    let message: String
    var resolvedAt: Date?
    var diagnostic: String { "code=\(code.rawValue); activity=\(activity ?? "none"); \(message)" }
    var displayMessage: String {
        resolvedAt == nil ? message : "Recovered: \(message) Active restriction settings have been reconciled; verify enforcement on your device."
    }
}

struct MonitoringRecoveryError: LocalizedError {
    let original: Error
    let persistence: Error
    var errorDescription: String? {
        "\(original.localizedDescription) Recovery could not be saved because shared storage failed: \(persistence.localizedDescription) Monitoring state needs attention; reopen BreakLoop when storage is available."
    }
}

// Shared adapter policy: both the real FamilyControls adapter and tests use this loader.
// Read/decode/validate once, then return a nonthrowing write using that exact selection.
struct ShieldSelectionLoader<Selection> {
    let load: () throws -> Selection?
    let supported: (Selection) -> Bool
    let apply: (Selection) -> Void
    var inspected: (Selection, Bool) -> Void = { _, _ in }

    func selection() throws -> Selection {
        let value: Selection?
        do { value = try load() }
        catch is DecodingError { throw SelectionFailure.corrupted }
        catch let error as SelectionFailure { throw error }
        catch { throw SelectionFailure.persistence(error) }
        guard let value else { throw SelectionFailure.missing }
        let accepted = supported(value)
        inspected(value, accepted)
        guard accepted else { throw SelectionFailure.unsupported }
        return value
    }
    func prepare() throws -> () -> Void {
        let value = try selection()
        return { apply(value) }
    }
}

enum SelectionFailure: LocalizedError {
    case missing, corrupted, unsupported, persistence(Error)
    var errorDescription: String? {
        switch self {
        case .missing: return "The saved app selection is missing. Select apps or categories in Rules and save them again."
        case .corrupted: return "The saved app selection could not be decoded. Select apps or categories in Rules and save them again."
        case .unsupported: return "The selection is empty or unsupported. Select up to 50 apps and 50 categories; website selections are not supported."
        case .persistence: return "The saved app selection could not be read from shared storage. Reopen BreakLoop when storage is available."
        }
    }
    static func isSelectionError(_ error: Error) -> Bool { error is SelectionFailure }
    static func classify(_ error: Error) -> MonitoringFailureCode {
        switch error as? SelectionFailure {
        case .missing: return .selectionMissing
        case .corrupted: return .selectionCorrupted
        case .unsupported: return .selectionUnsupported
        default: return .selectionUnavailable
        }
    }
}


// Keep adapter support policy testable without constructing opaque FamilyControls tokens.
enum ShieldSelectionSupport {
    static func isSupported(applications: Int, categories: Int, webDomains: Int) -> Bool {
        (applications > 0 || categories > 0) && applications <= 50 && categories <= 50 && webDomains == 0
    }
}


struct SelectionTokenCounts: Equatable {
    let applicationTokens: Int
    let categoryTokens: Int
    let webDomainTokens: Int
    var isSupported: Bool {
        ShieldSelectionSupport.isSupported(applications: applicationTokens, categories: categoryTokens, webDomains: webDomainTokens)
    }
    var hasAny: Bool { applicationTokens > 0 || categoryTokens > 0 || webDomainTokens > 0 }
    var validationMessage: String? {
        if webDomainTokens > 0 {
            return "This selection includes \(webDomainTokens) websites. BreakLoop v1.0 supports apps and categories only. Remove websites in the picker before saving or starting."
        }
        if applicationTokens > 50 || categoryTokens > 50 { return "Select at most 50 apps and 50 categories before saving or starting." }
        if !hasAny { return "Select at least one app or category before saving or starting." }
        return nil
    }
    var diagnosticCounts: [String: String] {
        ["applicationTokens": "\(applicationTokens)", "categoryTokens": "\(categoryTokens)", "webDomainTokens": "\(webDomainTokens)"]
    }
    // Testable save gate used by the real App Group adapter. A rejected selection is never altered
    // or partially saved, and callers must not persist configuration after rejection.
    func saveIfSupported(_ save: () throws -> Void) throws {
        guard isSupported else { throw SelectionFailure.unsupported }
        try save()
    }
}
