import Foundation

private final class ScheduledDashboardRead {
    let at: Date
    let callback: @MainActor () -> Void
    var cancelled = false
    init(at: Date, callback: @escaping @MainActor () -> Void) { self.at = at; self.callback = callback }
}
private final class ObservationFlag { var active = true }

private final class RuntimeSignalReceipt: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func receive() { lock.lock(); count += 1; lock.unlock() }
    var received: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor
private final class DashboardFixture {
    let lifecycle = Harness()
    var readFails = false
    var reconcileFails = false
    var observationFails = false
    var reads = 0
    var reconciliations = 0
    var registrations = 0
    var publications: [DashboardState] = []
    var logs: [[String: String]] = []
    var observations: [(ObservationFlag, @MainActor () -> Void)] = []
    var jobs: [ScheduledDashboardRead] = []
    var activeObservers: Int { observations.filter { $0.0.active }.count }
    var pendingJobs: Int { jobs.filter { !$0.cancelled }.count }

    lazy var sut = DashboardStateSynchronizer(read: { [unowned self] in
        reads += 1
        if readFails { throw InjectedFailure.persistence }
        return try lifecycle.store.readRuntime()
    }, reconcile: { [unowned self] in
        reconciliations += 1
        if reconcileFails { throw InjectedFailure.scheduling }
        try lifecycle.sut.reconcile()
    }, observe: { [unowned self] callback in
        if observationFails { throw InjectedFailure.persistence }
        registrations += 1
        let flag = ObservationFlag()
        observations.append((flag, callback))
        return RuntimeCancellation { flag.active = false }
    }, schedule: { [unowned self] delay, callback in
        let job = ScheduledDashboardRead(at: lifecycle.time.addingTimeInterval(delay), callback: callback)
        jobs.append(job)
        return RuntimeCancellation { job.cancelled = true }
    }, now: { [unowned self] in lifecycle.time },
       publish: { [unowned self] in publications.append($0) },
       log: { [unowned self] _, metadata in logs.append(metadata) })

    func notify() { for (flag, callback) in observations where flag.active { callback() } }
    func advance(_ seconds: TimeInterval) {
        lifecycle.time = lifecycle.time.addingTimeInterval(seconds)
        let due = jobs.filter { !$0.cancelled && $0.at <= lifecycle.time }
        jobs.removeAll { $0.cancelled || $0.at <= lifecycle.time }
        for job in due { job.callback() }
    }
}

@MainActor
func runDashboardSynchronizationTests() throws {
    do {
        var fixture: DashboardFixture? = DashboardFixture()
        fixture!.sut.activate()
        weak var synchronizer = fixture!.sut
        let flags = fixture!.observations.map { $0.0 }
        let jobs = fixture!.jobs
        fixture = nil
        check(synchronizer == nil, "Synchronizer deallocates without an observer/task retain cycle")
        synchronizer = nil
        check(flags.allSatisfy { !$0.active } && jobs.allSatisfy { $0.cancelled },
              "Deallocation cancels observers and all scheduled reads")
    }
    do {
        let f = DashboardFixture(); try f.lifecycle.sut.start()
        f.sut.activate()
        check(f.sut.state.mode == .monitoring && f.sut.state.canStopBreakLoop, "Normal authoritative state presents monitoring")
        let focus = MonitoringRuntime.focusName(f.lifecycle.store.state.snapshot!.id)
        try f.lifecycle.sut.threshold(name: focus, minute: nil) // extension transaction after activation
        f.notify()
        check(f.sut.state.mode == .cooldown, "Visible Dashboard observes extension cooldown commit")
        check(!f.sut.state.canStopBreakLoop, "Stop BreakLoop is absent for committed cooldown")
        check(f.sut.state.runtime == f.lifecycle.store.state, "Presentation contains one coherent authoritative record")
        let schedules = f.lifecycle.scheduleAttempts
        let publicationCount = f.publications.count
        for _ in 0..<5 { f.notify() }
        check(f.lifecycle.scheduleAttempts == schedules && f.reconciliations == 1,
              "Duplicate invalidations perform reads, never reconciliation or monitoring restart")
        check(f.publications.count == publicationCount, "Duplicate snapshots do not republish UI state")
        check(f.logs.contains { $0["cooldownId"] == f.lifecycle.store.state.cooldown?.id.uuidString && $0["observedAtEpoch"] != nil },
              "Observation diagnostics identify cooldown generation and timestamp")
        f.sut.deactivate()
    }
    do {
        let f = DashboardFixture(); try f.lifecycle.sut.start(); f.sut.activate()
        check(f.sut.state.mode == .monitoring, "Foreground can precede extension publication")
        let focus = MonitoringRuntime.focusName(f.lifecycle.store.state.snapshot!.id)
        try f.lifecycle.sut.threshold(name: focus, minute: nil)
        // Deliberately drop notification; bounded foreground read catches the subsequent commit.
        f.advance(0.2)
        check(f.sut.state.mode == .cooldown, "Bounded foreground recheck catches publication after first read")
        check(f.reconciliations == 1 && f.lifecycle.scheduleAttempts == 2, "Foreground recheck cannot duplicate schedules")
        f.advance(2)
        let reads = f.reads
        f.advance(10)
        check(f.reads == reads, "Foreground rechecks end instead of continuously polling")
        f.sut.deactivate()
    }
    do {
        let f = DashboardFixture(); try f.lifecycle.cooldown(); f.sut.activate()
        let initial = f.sut.state.runtime!.cooldown!
        let focusID = f.lifecycle.store.state.snapshot!.id
        try f.lifecycle.sut.extendCooldown(minutes: 15); f.notify()
        check(f.sut.state.runtime!.cooldown!.endsAt == initial.endsAt.addingTimeInterval(900), "First extension displays +15 minutes")
        try f.lifecycle.sut.extendCooldown(minutes: 15); f.notify()
        let final = f.sut.state.runtime!.cooldown!
        check(final.endsAt == initial.endsAt.addingTimeInterval(1800), "Second extension displays total +30 minutes")
        check(f.lifecycle.store.state.snapshot!.id == focusID && f.lifecycle.monitored.count == 2,
              "Two extensions preserve normal monitoring identity and activity count")
        f.notify() // old/delayed signal contains no old payload
        try f.lifecycle.sut.intervalEnded(name: MonitoringRuntime.cooldownName(initial.id))
        f.notify()
        check(f.sut.state.runtime!.cooldown == final, "Delayed notification and stale callback cannot restore an old deadline")
        f.sut.deactivate()
    }
    do {
        let f = DashboardFixture(); try f.lifecycle.cooldown(); f.sut.activate()
        let priorID = f.lifecycle.store.state.snapshot!.id
        let end = f.lifecycle.store.state.cooldown!.endsAt
        let schedules = f.lifecycle.scheduleAttempts
        f.advance(end.timeIntervalSince(f.lifecycle.time) + 0.1)
        check(f.sut.state.mode == .monitoring && f.sut.state.runtime!.cooldown == nil,
              "Deadline reconciliation removes stale cooldown presentation")
        check(f.lifecycle.store.state.snapshot!.id != priorID && f.lifecycle.scheduleAttempts == schedules + 1,
              "Actual cooldown completion grants exactly one fresh monitoring cycle")
        f.notify(); f.notify()
        check(f.lifecycle.scheduleAttempts == schedules + 1, "Post-expiry UI signals cannot reschedule another cycle")
        f.sut.deactivate()
    }
    do {
        let f = DashboardFixture(); try f.lifecycle.cooldown(); try f.lifecycle.sut.startDeepFocus(minutes: 60)
        f.sut.activate()
        check(f.sut.state.mode == .deepFocus && !f.sut.state.canStopBreakLoop, "Deep Focus takes consistent priority over cooldown")
        try f.lifecycle.sut.stopDeepFocus(); f.notify()
        check(f.sut.state.mode == .cooldown, "Ending Deep Focus exposes existing cooldown")
        f.sut.deactivate()
    }
    do {
        let f = DashboardFixture(); try f.lifecycle.sut.start()
        f.reconcileFails = true; f.sut.activate()
        check(f.sut.state.mode == .failure && !f.sut.state.canStopBreakLoop, "Reconciliation error does not claim synchronized Active state")
        let schedules = f.lifecycle.scheduleAttempts
        f.advance(2); f.notify()
        check(f.sut.state.mode == .failure && f.lifecycle.scheduleAttempts == schedules,
              "Read-only updates retain reconciliation failure without retry loops")
        f.sut.deactivate(); f.reconcileFails = false; f.sut.activate()
        check(f.sut.state.mode == .monitoring, "Next foreground can recover after reconciliation succeeds")
        f.readFails = true; f.notify()
        check(f.sut.state.mode == .failure && f.sut.state.errorMessage != nil, "Storage read failure is explicit and recoverable")
        f.readFails = false; f.notify()
        check(f.sut.state.mode == .monitoring, "Notification can recover after storage reads resume")
        f.sut.deactivate()
    }
    do {
        let f = DashboardFixture(); try f.lifecycle.cooldown(); f.sut.activate()
        f.reconcileFails = true
        let deadline = f.lifecycle.store.state.cooldown!.endsAt
        f.advance(deadline.timeIntervalSince(f.lifecycle.time) + 0.1)
        check(f.sut.state.mode == .failure, "Expiry reconciliation failure is presented instead of pretending unlock")
        let attempts = f.reconciliations
        f.notify(); f.advance(1); f.notify(); f.advance(100)
        check(f.reconciliations == attempts, "Failed expired owner gets one reconciliation attempt, not an infinite timer loop")
        f.sut.deactivate()
    }
    do {
        let f = DashboardFixture(); try f.lifecycle.sut.start()
        let schedules = f.lifecycle.scheduleAttempts
        for _ in 0..<10 {
            f.sut.activate(); f.sut.activate()
            check(f.activeObservers == 1, "Repeated appearance installs one observer")
            let queuedOldSignal = f.observations.last!.1
            f.sut.deactivate(); f.sut.deactivate()
            check(f.activeObservers == 0 && f.pendingJobs == 0, "Background cancels observers, delayed reads and expiry work")
            let reads = f.reads
            queuedOldSignal(); f.advance(2)
            check(f.reads == reads, "Queued callbacks from inactive epoch do not access storage")
        }
        check(f.registrations == 10 && f.reconciliations == 10, "Foreground cycles neither leak observers nor duplicate reconciliations")
        check(f.lifecycle.scheduleAttempts == schedules, "Background/foreground cycles never recreate a valid schedule")
    }
    do {
        let f = DashboardFixture(); f.observationFails = true; f.sut.activate()
        check(f.sut.state.mode == .failure && f.sut.state.errorMessage != nil, "Observer installation failure cannot claim live synchronization")
        f.sut.deactivate()
        let state = DashboardState(runtime: MonitoringRuntime())
        check(state.mode == .inactive && !state.canStopBreakLoop, "Empty authoritative runtime presents inactive")
    }
    do {
        // Exercise production file-store notification ordering, unchanged commits and throw-after-write.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var signals = 0
        let reader = RuntimeFileStore(directory: directory)
        let writer = RuntimeFileStore(directory: directory, didChange: {
            signals += 1
            // This would deadlock if publication occurred under the file lock.
            try! reader.withRuntimeLock { _ = try reader.readRuntime() }
        })
        try writer.withRuntimeLock { try writer.writeRuntime(MonitoringRuntime()) }
        check(signals == 1, "Successful runtime publication signals after lock release")
        try writer.withRuntimeLock { try writer.writeRuntime(MonitoringRuntime()) }
        check(signals == 1, "Unchanged reconciliation writes do not create notification loops")
        var next = MonitoringRuntime(); next.snapshot = CycleSnapshot(configuration: .default)
        fails { try writer.withRuntimeLock { try writer.writeRuntime(next); throw InjectedFailure.scheduling } }
        let committed = try reader.readRuntime()
        check(signals == 2 && committed == next, "Committed attention/error transitions still signal when operation throws")
        try FileManager.default.removeItem(at: writer.recordURL)
        try FileManager.default.createDirectory(at: writer.recordURL, withIntermediateDirectories: false)
        fails { try writer.withRuntimeLock { try writer.writeRuntime(MonitoringRuntime()) } }
        check(signals == 2, "Failed persistence never posts a successful invalidation")
    }
    do {
        let receipt = RuntimeSignalReceipt()
        let observation = try RuntimeChangeSignal.observe { receipt.receive() }
        let writer = Process()
        writer.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        writer.arguments = ["--post-runtime-change"]
        try writer.run(); writer.waitUntilExit()
        check(writer.terminationStatus == 0, "Separate process posts the production Darwin invalidation")
        let timeout = Date().addingTimeInterval(2)
        while receipt.received == 0 && Date() < timeout {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        check(receipt.received > 0, "Production Darwin observer receives another process's signal")
        observation.cancel(); observation.cancel()
    }
    do {
        // First-run selection state and validation differentiation
        let empty = DashboardSelectionState(counts: SelectionTokenCounts(applicationTokens: 0, categoryTokens: 0, webDomainTokens: 0))
        check(empty == .empty && empty.isEmpty && !empty.isSupported, "Empty selection maps to first-run empty state")
        check(empty.validationOrReadErrorMessage == nil, "First-run empty selection does not emit a destructive error message")

        let valid = DashboardSelectionState(counts: SelectionTokenCounts(applicationTokens: 3, categoryTokens: 1, webDomainTokens: 0))
        check(valid.isSupported && !valid.isEmpty && valid.validationOrReadErrorMessage == nil, "Supported selection is valid with no error")

        let websites = DashboardSelectionState(counts: SelectionTokenCounts(applicationTokens: 2, categoryTokens: 0, webDomainTokens: 1))
        check(websites.hasUnsupportedWebsites && !websites.isSupported && websites.validationOrReadErrorMessage != nil, "Website selection is flagged as unsupported with localized repair guidance")

        let overLimit = DashboardSelectionState(counts: SelectionTokenCounts(applicationTokens: 51, categoryTokens: 0, webDomainTokens: 0))
        check(!overLimit.isSupported && !overLimit.hasUnsupportedWebsites && overLimit.validationOrReadErrorMessage != nil, "Over-limit selection reports limit error")

        let readFailure = DashboardSelectionState(counts: valid == .empty ? nil : SelectionTokenCounts(applicationTokens: 1, categoryTokens: 0, webDomainTokens: 0), readError: "Storage corrupted")
        check(readFailure == .readFailure(message: "Storage corrupted") && !readFailure.isSupported && readFailure.validationOrReadErrorMessage == "Storage corrupted", "Selection read error takes precedence over cached counts")
    }
    do {
        // DeepFocusLaunchController sheet presentation, error retention on failure, and dismissal only on success
        let launcher = DeepFocusLaunchController()
        launcher.presentSheet()
        check(launcher.isSheetPresented && launcher.errorMessage == nil && !launcher.isStarting, "Presenting Deep Focus sheet clears prior error")

        let blockedByMode = launcher.start(durationMinutes: 60, canConfigure: false) { _ in }
        check(!blockedByMode && launcher.isSheetPresented && launcher.errorMessage != nil, "Blocked Deep Focus launch keeps sheet open with localized error")

        let invalidDuration = launcher.start(durationMinutes: 5, canConfigure: true) { _ in }
        check(!invalidDuration && launcher.isSheetPresented && launcher.errorMessage == LifecycleError.invalidDuration.localizedDescription, "Invalid Deep Focus duration keeps sheet open with duration error")

        let failedSchedule = launcher.start(durationMinutes: 60, canConfigure: true) { _ in
            throw LifecycleError.invalidSchedule
        }
        check(!failedSchedule && launcher.isSheetPresented && launcher.errorMessage == LifecycleError.invalidSchedule.localizedDescription, "Failed Deep Focus start keeps sheet open and surfaces thrown error")

        var nestedDuplicateResult = true
        var startInvocations = 0
        let succeeded = launcher.start(durationMinutes: 60, canConfigure: true) { minutes in
            startInvocations += 1
            check(minutes == 60 && launcher.isStarting, "Launcher marks in-flight start while executing")
            nestedDuplicateResult = launcher.start(durationMinutes: 60, canConfigure: true) { _ in
                startInvocations += 1
            }
        }
        check(succeeded && startInvocations == 1 && !nestedDuplicateResult, "Duplicate rapid tap while starting is rejected without re-running start")
        check(!launcher.isSheetPresented && launcher.errorMessage == nil && !launcher.isStarting, "Successful Deep Focus start dismisses sheet and clears error")
    }
    do {
        // ConfigurationSaveController explicit save, clamping, validation, and rollback on failure
        let initial = CycleConfiguration(usageLimitMinutes: 20, restDurationMinutes: 15)
        var controller = ConfigurationSaveController(committed: initial)
        check(!controller.hasUnsavedChanges && controller.committed == initial, "Initial save controller has no unsaved changes")

        controller.setUsageLimit(30)
        controller.setRestDuration(25)
        check(controller.hasUnsavedChanges && controller.pending == CycleConfiguration(usageLimitMinutes: 30, restDurationMinutes: 25), "Pending edits are tracked separately from committed configuration")

        let rejectedSelection = controller.save(
            selectionCounts: SelectionTokenCounts(applicationTokens: 1, categoryTokens: 0, webDomainTokens: 2)
        ) { _ in
            fatalError("Persist must not be called when selection is invalid")
        }
        check(!rejectedSelection && controller.committed == initial && controller.errorMessage != nil, "Invalid selection rejects save, preserves committed config, and surfaces validation error")

        struct RawStorageFailure: Error {}
        let failedWrite = controller.save(
            selectionCounts: SelectionTokenCounts(applicationTokens: 2, categoryTokens: 0, webDomainTokens: 0)
        ) { _ in
            throw RawStorageFailure()
        }
        check(!failedWrite && controller.committed == initial && controller.pending.usageLimitMinutes == 30, "Failed persistence preserves last valid committed configuration and retains pending edits for retry")
        check(controller.errorMessage == ConfigurationPersistenceError.writeFailed(reason: "").localizedDescription, "Failed persistence surfaces localized shared storage error")

        var persisted: CycleConfiguration?
        let saved = controller.save(
            selectionCounts: SelectionTokenCounts(applicationTokens: 2, categoryTokens: 0, webDomainTokens: 0)
        ) { config in
            persisted = config
        }
        check(saved && persisted == CycleConfiguration(usageLimitMinutes: 30, restDurationMinutes: 25), "Retry save persists pending configuration")
        check(controller.committed == persisted && !controller.hasUnsavedChanges && controller.errorMessage == nil, "Successful save updates committed configuration and clears error")

        controller.setUsageLimit(45)
        check(controller.hasUnsavedChanges, "Subsequent edit marks unsaved changes")
        controller.revertPendingToCommitted()
        check(!controller.hasUnsavedChanges && controller.pending == controller.committed && controller.errorMessage == nil, "Reverting unsaved changes restores committed configuration")
    }

}
