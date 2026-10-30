import Foundation

// Presentation is replaced once per authoritative read, never assembled from separate key reads.
struct DashboardState: Equatable {
    enum Mode: String { case loading, inactive, monitoring, cooldown, deepFocus, failure }
    let runtime: MonitoringRuntime?
    let mode: Mode
    let errorMessage: String?
    let synchronizationError: String?
    static let loading = DashboardState(runtime: nil, mode: .loading, errorMessage: nil)
    // Derive the sibling cycle card from the same verified record; never mutate persisted ownership.
    var usageCycleState: DashboardState {
        guard var runtime else { return self }
        runtime.deepFocus = nil
        return DashboardState(runtime: runtime, synchronizationError: synchronizationError)
    }
    var canStopBreakLoop: Bool { mode == .monitoring }
    var canOfferInactiveStarts: Bool { mode == .inactive }
    var canConfigureDeepFocus: Bool { mode == .inactive || mode == .monitoring }
    var canStopRecordedBreakLoop: Bool {
        runtime?.pendingTransition == nil && mode == .failure && synchronizationError == nil && runtime?.snapshot != nil
            && runtime?.cooldown == nil && runtime?.deepFocus == nil
    }
    var canRetryBreakLoop: Bool {
        runtime?.pendingTransition == nil && mode == .failure && synchronizationError == nil && runtime != nil
            && runtime?.snapshot == nil && runtime?.cooldown == nil && runtime?.deepFocus == nil
    }
    var recoveryDescription: String {
        guard synchronizationError == nil, let runtime else {
            return String(localized: "Current session state could not be verified. Refresh status before starting another session.")
        }
        if runtime.deepFocus != nil || runtime.cooldown != nil {
            return String(localized: "A restriction is still recorded. Refresh status; recovery will preserve existing ownership.")
        }
        if runtime.snapshot != nil { return String(localized: "A Usage Cycle is still recorded. Review apps and refresh status, or stop the recorded session before retrying.") }
        return String(localized: "The Usage Cycle was interrupted. Review the saved apps, refresh status, then retry.")
    }

    init(runtime: MonitoringRuntime?, synchronizationError: String? = nil) {
        self.runtime = runtime
        self.synchronizationError = synchronizationError
        if let synchronizationError { errorMessage = synchronizationError }
        else if let attention = runtime?.attention, attention.resolvedAt == nil, attention.code.isSelectionFailure {
            errorMessage = String(localized: "dashboard.previousSelection", defaultValue: "Previous selection issue (\(attention.occurredAt.formatted(date: .omitted, time: .standard))): \(attention.localizedReason) Review the current saved selection before retrying.")
        } else { errorMessage = runtime?.attention?.displayMessage }
        if synchronizationError != nil || runtime == nil { mode = .failure }
        else if runtime?.pendingTransition != nil { mode = .loading }
        // Keep an elapsed owner visible until lifecycle reconciliation actually removes it.
        else if runtime?.deepFocus != nil { mode = .deepFocus }
        else if runtime?.cooldown != nil { mode = .cooldown }
        else if runtime?.attention != nil && runtime?.attention?.resolvedAt == nil { mode = .failure }
        else if runtime?.snapshot != nil { mode = .monitoring }
        else { mode = .inactive }
    }
    private init(runtime: MonitoringRuntime?, mode: Mode, errorMessage: String?) {
        self.runtime = runtime; self.mode = mode; self.errorMessage = errorMessage; synchronizationError = nil
    }
}

@MainActor
final class DashboardStateSynchronizer {
    typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> RuntimeCancellation
    private let read: () throws -> MonitoringRuntime
    private let reconcile: () throws -> Void
    private let observe: (@escaping @MainActor () -> Void) throws -> RuntimeCancellation
    private let schedule: Schedule
    private let now: () -> Date
    private let publish: (DashboardState) -> Void
    private let log: (String, [String: String]) -> Void
    private var observer: RuntimeCancellation?
    private var rechecks: [RuntimeCancellation] = []
    private var expiration: RuntimeCancellation?
    private var attemptedExpirations: Set<Date> = []
    private var epoch = 0
    private var isActive = false
    private var reconciliationError: String?
    private var observerError: String?
    private(set) var state = DashboardState.loading

    init(read: @escaping () throws -> MonitoringRuntime, reconcile: @escaping () throws -> Void,
         observe: @escaping (@escaping @MainActor () -> Void) throws -> RuntimeCancellation,
         schedule: @escaping Schedule = DashboardStateSynchronizer.scheduleRead,
         now: @escaping () -> Date = Date.init,
         publish: @escaping (DashboardState) -> Void,
         log: @escaping (String, [String: String]) -> Void = { _, _ in }) {
        self.read = read; self.reconcile = reconcile; self.observe = observe
        self.schedule = schedule; self.now = now; self.publish = publish; self.log = log
    }

    static func scheduleRead(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) -> RuntimeCancellation {
        let task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return RuntimeCancellation { task.cancel() }
    }

    func activate() {
        guard !isActive else { return }
        isActive = true; epoch += 1
        let currentEpoch = epoch
        attemptedExpirations.removeAll()
        observerError = nil
        do {
            // Install before reading so a publication during foreground entry cannot fall in a gap.
            observer = try observe { [weak self] in
                guard let self, self.isActive, self.epoch == currentEpoch else { return }
                self.refresh(reason: "invalidation")
            }
        } catch { observerError = String(localized: "dashboard.liveUnavailable", defaultValue: "Live state updates are unavailable. Reopen BreakLoop to refresh. \(error.localizedDescription)") }
        refresh(reason: "foreground_initial")
        reconcileAndRefresh(reason: "foreground_reconciled")
        // Read-only, bounded coverage for publication just after activation or coalesced signals.
        rechecks = [0.15, 0.6, 1.5].map { delay in
            schedule(delay) { [weak self] in
                guard let self, self.isActive, self.epoch == currentEpoch else { return }
                self.refresh(reason: "foreground_recheck")
            }
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false; epoch += 1
        observer?.cancel(); observer = nil
        rechecks.forEach { $0.cancel() }; rechecks.removeAll()
        expiration?.cancel(); expiration = nil
    }

    func refresh(reason: String = "manual") {
        do {
            let runtime = try read() // Exactly one runtime record; inventory is lifecycle input, not UI truth.
            update(DashboardState(runtime: runtime, synchronizationError: reconciliationError ?? observerError), reason: reason)
            scheduleExpiration(runtime)
        } catch {
            update(DashboardState(runtime: state.runtime, synchronizationError: error.localizedDescription), reason: reason)
        }
    }

    func recover() { reconcileAndRefresh(reason: "user_recovery") }

    func actionCompleted() {
        reconciliationError = nil
        refresh(reason: "action_completed")
    }

    // Lifecycle reconciliation is limited to foreground entry and one attempt per owner deadline.
    // Notification/manual refreshes never schedule DeviceActivity or write restrictions.
    private func reconcileAndRefresh(reason: String) {
        do { try reconcile(); reconciliationError = nil }
        catch { reconciliationError = error.localizedDescription }
        refresh(reason: reason)
    }

    private func update(_ next: DashboardState, reason: String) {
        var metadata = ["reason": reason, "mode": next.mode.rawValue, "observedAt": now().ISO8601Format(), "observedAtEpoch": "\(now().timeIntervalSince1970)",
                        "snapshotId": next.runtime?.snapshot?.id.uuidString ?? "none",
                        "cooldownId": next.runtime?.cooldown?.id.uuidString ?? "none",
                        "cooldownEnd": next.runtime?.cooldown?.endsAt.ISO8601Format() ?? "none"]
        metadata["attentionCode"] = next.runtime?.attention?.code.rawValue ?? "none"
        metadata["attentionOccurredAt"] = next.runtime?.attention.map { "\($0.occurredAt.timeIntervalSince1970)" } ?? "none"
        metadata["failureSource"] = next.synchronizationError != nil ? "current_synchronization" : (next.runtime?.attention != nil ? "persisted_attention" : "none")
        metadata["synchronized"] = next.mode == .failure ? "false" : "true"
        guard next != state else { return }
        log("dashboard_runtime_observed", metadata)
        state = next; publish(next)
    }

    private func scheduleExpiration(_ runtime: MonitoringRuntime) {
        guard isActive else { return }
        expiration?.cancel(); expiration = nil
        let deadlines = [runtime.cooldown?.endsAt, runtime.deepFocus?.endsAt].compactMap { $0 }
        attemptedExpirations.formIntersection(Set(deadlines))
        guard let deadline = deadlines.filter({ !attemptedExpirations.contains($0) }).min() else { return }
        let currentEpoch = epoch
        expiration = schedule(max(0.05, deadline.timeIntervalSince(now()) + 0.05)) { [weak self] in
            guard let self, self.isActive, self.epoch == currentEpoch else { return }
            self.attemptedExpirations.insert(deadline)
            self.reconcileAndRefresh(reason: "owner_deadline")
        }
    }
}

enum DashboardSelectionState: Equatable {
    case empty
    case valid(SelectionTokenCounts)
    case unsupportedWebsites(SelectionTokenCounts, message: String)
    case invalidLimits(SelectionTokenCounts, message: String)
    case readFailure(message: String)

    init(counts: SelectionTokenCounts?, readError: String? = nil) {
        if let readError {
            self = .readFailure(message: readError)
            return
        }
        guard let counts, counts.hasAny else {
            self = .empty
            return
        }
        if counts.isSupported {
            self = .valid(counts)
        } else if counts.webDomainTokens > 0 {
            self = .unsupportedWebsites(counts, message: counts.validationMessage ?? SelectionFailure.unsupported.localizedDescription)
        } else {
            self = .invalidLimits(counts, message: counts.validationMessage ?? SelectionFailure.unsupported.localizedDescription)
        }
    }

    var isSupported: Bool {
        if case .valid = self { return true }
        return false
    }

    var isEmpty: Bool {
        self == .empty
    }

    var hasUnsupportedWebsites: Bool {
        if case .unsupportedWebsites = self { return true }
        return false
    }

    var validationOrReadErrorMessage: String? {
        switch self {
        case .empty, .valid:
            return nil
        case .unsupportedWebsites(_, let message), .invalidLimits(_, let message), .readFailure(let message):
            return message
        }
    }
}

// Read-only UI composition: active/recovering runtime always outranks selection setup.
enum DashboardExperiencePresentation: Equatable {
    case needsSelection, ready, repairSelection, selectionUnavailable
    case runtime(DashboardState.Mode)

    init(mode: DashboardState.Mode, selection: DashboardSelectionState) {
        guard mode == .inactive else { self = .runtime(mode); return }
        switch selection {
        case .empty: self = .needsSelection
        case .valid: self = .ready
        case .unsupportedWebsites, .invalidLimits: self = .repairSelection
        case .readFailure: self = .selectionUnavailable
        }
    }
}

// A companion status, not another timer or a pause/freeze state.
enum DashboardFocusCompanionState: Equatable {
    case none, usageCycle, cooldown, needsAttention

    init(state: DashboardState) {
        guard state.mode == .deepFocus, let runtime = state.runtime else { self = .none; return }
        if runtime.cooldown != nil { self = .cooldown }
        else if runtime.snapshot != nil {
            self = runtime.attention?.resolvedAt == nil && runtime.attention != nil ? .needsAttention : .usageCycle
        } else { self = .none }
    }
}

final class DeepFocusLaunchController {
    static let supportedRange = 15...(24 * 60)

    private(set) var isSheetPresented: Bool = false
    private(set) var isStarting: Bool = false
    private(set) var errorMessage: String?

    func presentSheet() {
        guard !isStarting else { return }
        errorMessage = nil
        isSheetPresented = true
    }

    func dismissSheet() {
        guard !isStarting else { return }
        isSheetPresented = false
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    @discardableResult
    func start(
        durationMinutes: Int,
        canConfigure: Bool,
        performStart: (Int) throws -> Void
    ) -> Bool {
        guard !isStarting else { return false }
        guard canConfigure else {
            errorMessage = String(localized: "Refresh monitoring status before starting Deep Focus.")
            return false
        }
        guard Self.supportedRange.contains(durationMinutes) else {
            errorMessage = LifecycleError.invalidDuration.localizedDescription
            return false
        }
        isStarting = true
        defer { isStarting = false }
        do {
            try performStart(durationMinutes)
            errorMessage = nil
            isSheetPresented = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

enum ConfigurationPersistenceError: LocalizedError, Equatable {
    case writeFailed(reason: String)

    var errorDescription: String? {
        String(
            localized: "Settings could not be saved to shared storage. Try again.",
            table: "SharedErrors"
        )
    }
}

struct ConfigurationSaveController: Equatable {
    private(set) var committed: CycleConfiguration
    var pending: CycleConfiguration
    private(set) var errorMessage: String?

    init(committed: CycleConfiguration = .default) {
        self.committed = committed
        self.pending = committed
        self.errorMessage = nil
    }

    var hasUnsavedChanges: Bool {
        pending != committed
    }

    mutating func reload(committed: CycleConfiguration) {
        self.committed = committed
        self.pending = committed
        self.errorMessage = nil
    }

    mutating func setUsageLimit(_ minutes: Int) {
        pending = CycleConfiguration(
            usageLimitMinutes: minutes,
            restDurationMinutes: pending.restDurationMinutes
        )
    }

    mutating func setRestDuration(_ minutes: Int) {
        pending = CycleConfiguration(
            usageLimitMinutes: pending.usageLimitMinutes,
            restDurationMinutes: minutes
        )
    }

    mutating func revertPendingToCommitted() {
        pending = committed
        errorMessage = nil
    }

    @discardableResult
    mutating func save(
        selectionCounts: SelectionTokenCounts? = nil,
        persist: (CycleConfiguration) throws -> Void
    ) -> Bool {
        if let selectionCounts, !selectionCounts.isSupported {
            errorMessage = selectionCounts.validationMessage ?? SelectionFailure.unsupported.localizedDescription
            return false
        }
        let candidate = CycleConfiguration(
            usageLimitMinutes: pending.usageLimitMinutes,
            restDurationMinutes: pending.restDurationMinutes
        )
        do {
            try persist(candidate)
            committed = candidate
            pending = candidate
            errorMessage = nil
            return true
        } catch let error as LocalizedError where error.errorDescription != nil {
            errorMessage = error.localizedDescription
            return false
        } catch {
            errorMessage = ConfigurationPersistenceError.writeFailed(reason: error.localizedDescription).localizedDescription
            return false
        }
    }
}
