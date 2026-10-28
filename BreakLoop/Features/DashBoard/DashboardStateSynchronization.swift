import Foundation

// Presentation is replaced once per authoritative read, never assembled from separate key reads.
struct DashboardState: Equatable {
    enum Mode: String { case loading, inactive, monitoring, cooldown, deepFocus, failure }
    let runtime: MonitoringRuntime?
    let mode: Mode
    let errorMessage: String?
    static let loading = DashboardState(runtime: nil, mode: .loading, errorMessage: nil)
    var canStopBreakLoop: Bool { mode == .monitoring }

    init(runtime: MonitoringRuntime?, synchronizationError: String? = nil) {
        self.runtime = runtime
        errorMessage = synchronizationError ?? runtime?.attention?.displayMessage
        if synchronizationError != nil || runtime == nil { mode = .failure }
        // Keep an elapsed owner visible until lifecycle reconciliation actually removes it.
        else if runtime?.deepFocus != nil { mode = .deepFocus }
        else if runtime?.cooldown != nil { mode = .cooldown }
        else if runtime?.attention != nil && runtime?.attention?.resolvedAt == nil { mode = .failure }
        else if runtime?.snapshot != nil { mode = .monitoring }
        else { mode = .inactive }
    }
    private init(runtime: MonitoringRuntime?, mode: Mode, errorMessage: String?) {
        self.runtime = runtime; self.mode = mode; self.errorMessage = errorMessage
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
        } catch { observerError = "Live state updates are unavailable. Reopen BreakLoop to refresh. \(error.localizedDescription)" }
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
        metadata["synchronized"] = next.mode == .failure ? "false" : "true"
        log("dashboard_runtime_observed", metadata)
        guard next != state else { return }
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
