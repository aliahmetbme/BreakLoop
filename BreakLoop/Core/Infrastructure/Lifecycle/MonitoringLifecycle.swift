import Foundation

// One atomic runtime record; configuration and the user's selection remain in their existing keys.
struct MonitoringRuntime: Codable, Equatable {
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
    // Must serialize *across processes*, including the entire schedule/commit/shield operation.
    func withRuntimeLock<T>(_ body: () throws -> T) throws -> T
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

    private func withOperationLock(_ action: String, _ work: () throws -> Void) throws {
        try operation(action) { try storage.withRuntimeLock(work) }
    }

    private func report(_ event: String, _ detail: String, metadata: [String: String] = [:]) {
        logger(event, detail, metadata)
    }

    // Preparation and scheduling can fail before publication. ManagedSettings writes after
    // publication use the already validated/captured selection and have no throwing API.
    private func commit(_ proposed: MonitoringRuntime, replacing old: MonitoringRuntime,
                        clearsSelectionAttentionOnStart: Bool = false,
                        start: () throws -> Void = {}) throws {
        var next = proposed
        let apply: () -> Void
        do {
            apply = next.ownsShield(at: now()) ? try driver.prepareShield() : driver.clearShield
        } catch {
            try recordSelectionFailure(error, state: old)
            throw error
        }
        if next.ownsShield(at: now()), next.attention?.code.isSelectionFailure == true, next.attention?.resolvedAt == nil {
            next.attention?.resolvedAt = now()
        }
        let added = next.activityNames.filter { !old.activityNames.contains($0) }
        do {
            try start()
            // A validated, successfully scheduled fresh focus cycle supersedes an old selection
            // failure even when no shield is owned (the normal post-cooldown state).
            if clearsSelectionAttentionOnStart, next.attention?.code.isSelectionFailure == true {
                next.attention = nil
            }
            try storage.writeRuntime(next)
        } catch {
            driver.stop(added)
            report("transition_failed", String(describing: error))
            throw error
        }
        stopObsolete(next)
        if next.ownsShield(at: now()) { apply() } else { driver.clearShield() }
    }

    private func stopObsolete(_ next: MonitoringRuntime) {
        driver.stop(driver.activities().filter { $0.hasPrefix("breakloop.") && !next.activityNames.contains($0) })
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
        var interrupted = old
        interrupted.snapshot = nil; interrupted.checkpoint = nil
        interrupted.attention = MonitoringAttention(code: code, occurredAt: now(),
            activity: old.snapshot.map { MonitoringRuntime.focusName($0.id) },
            message: "BreakLoop monitoring was interrupted. \(error.localizedDescription) Fix the problem and start BreakLoop again.")
        report("normal_cycle_interrupted", interrupted.attention!.diagnostic,
               metadata: ["failureCode": code.rawValue, "activity": interrupted.attention!.activity ?? "none",
                          "originalErrorDomain": (error as NSError).domain, "originalErrorCode": "\((error as NSError).code)"])
        do { try storage.writeRuntime(interrupted) } catch let persistenceError {
            if let snapshot = old.snapshot { driver.stop([MonitoringRuntime.focusName(snapshot.id)]) }
            report("interruption_persistence_failed", "original=\(error); persistence=\(persistenceError)",
                   metadata: ["failureCode": MonitoringFailureCode.runtimePersistence.rawValue,
                              "activity": interrupted.attention!.activity ?? "none",
                              "originalFailureCode": code.rawValue, "safeStatePersisted": "false"])
            throw MonitoringRecoveryError(original: error, persistence: persistenceError)
        }
        stopObsolete(interrupted)
        // Preserve an existing Deep Focus shield without reloading a possibly broken selection.
        // No new shield is introduced by interruption, and expired/no owners can safely clear.
        if !interrupted.ownsShield(at: now()) { driver.clearShield() }
        throw error
    }

    func start() throws {
        try withOperationLock("start_breakloop") {
            let old = try storage.readRuntime()
            if let snapshot = old.snapshot,
               old.legacyFocus == true || driver.activities().contains(MonitoringRuntime.focusName(snapshot.id)) {
                return // Repeated Start preserves a valid session; explicit Start can replace a missing generation.
            }
            var next = old
            let snapshot = CycleSnapshot(configuration: configuration(), startedAt: now())
            next.snapshot = snapshot; next.checkpoint = nil; next.legacyFocus = nil; next.attention = nil
            try commit(next, replacing: old) { try driver.startFocus(snapshot) }
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
            try commit(next, replacing: old) {
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
            try commit(next, replacing: old) {
                try driver.startDeadline(MonitoringRuntime.cooldownName(deadline.id), deadline.endsAt)
            }
        }
    }

    func intervalEnded(name: String) throws {
        try withOperationLock("interval_end_callback") {
            let state = try storage.readRuntime()
            let valid = state.cooldown.map { state.cooldownName == name && $0.endsAt <= now() } == true
                || state.deepFocus.map { state.deepFocusName == name && $0.endsAt <= now() } == true
            guard valid else { report("stale_interval_rejected", name); return }
            try reconcileLocked(state)
        }
    }

    func intervalStarted(name: String) throws {
        try withOperationLock("interval_start_callback") {
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
        let currentNames = driver.activities()
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
            try commit(next, replacing: old, clearsSelectionAttentionOnStart: snapshotToStart != nil) {
                if let snapshotToStart { try driver.startFocus(snapshotToStart) }
            }
        } catch {
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
                stopObsolete(next)
                if !next.ownsShield(at: now()) { driver.clearShield() }
            } else if snapshotToStart != nil || cooldownExpired || next.deepFocus != old.deepFocus {
                next.snapshot = nil; next.checkpoint = nil
                try commit(next, replacing: old)
            }
            throw error
        }
    }

    func threshold(name: String, minute: Int?) throws {
        try withOperationLock("threshold_callback") {
            let old = try storage.readRuntime()
            guard let snapshot = old.snapshot, name == MonitoringRuntime.focusName(snapshot.id),
                  old.cooldown == nil, driver.activities().contains(name) else { report("stale_threshold_rejected", name); return }
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
                try commit(next, replacing: old, clearsSelectionAttentionOnStart: true) { try driver.startFocus(fresh) }
            } else if minute == nil {
                let deadline = RestrictionDeadline(endsAt: Date(timeIntervalSince1970: ceil(now().timeIntervalSince1970 + Double(snapshot.restDurationMinutes) * 60)))
                next.cooldown = deadline; next.legacyCooldown = nil; next.checkpoint = nil
                var phase: MonitoringFailureCode = .selectionUnavailable
                do {
                    try commit(next, replacing: old) {
                        phase = .cooldownScheduling
                        try driver.startDeadline(MonitoringRuntime.cooldownName(deadline.id), deadline.endsAt)
                        phase = .runtimePersistence
                    }
                    report("cooldown_started", "Cooldown publication completed.", metadata: ["activity": MonitoringRuntime.cooldownName(deadline.id), "endsAt": deadline.endsAt.ISO8601Format()])
                } catch {
                    let original = (error as? MonitoringRecoveryError)?.original ?? error
                    let code = phase == .selectionUnavailable ? SelectionFailure.classify(original) : phase
                    try interrupt(old, error: error, code: code)
                }
            } else {
                next.checkpoint = UsageCheckpointState(usageMinute: usage, timestamp: now())
                try storage.writeRuntime(next)
            }
        }
    }
}

enum LifecycleError: LocalizedError {
    case invalidDuration, invalidSchedule, storageUnavailable, monitorUnavailable
    var errorDescription: String? {
        switch self {
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
