import Foundation
import Darwin

private let processClock = Date(timeIntervalSince1970: 1_800_000_000)
private func inventoryURL(_ directory: URL) -> URL { directory.appendingPathComponent("test-inventory.json") }
private func loadInventory(_ directory: URL) throws -> [String] {
    try JSONDecoder().decode([String].self, from: Data(contentsOf: inventoryURL(directory)))
}
private func saveInventory(_ names: [String], _ directory: URL) throws {
    try JSONEncoder().encode(names).write(to: inventoryURL(directory), options: .atomic)
}

// Child reaches the real unlocked scheduling boundary, then stops itself so the parent
// can force-kill it. The runtime record is real production JSON guarded by real flock.
func runInflightWorker(directory path: String) throws {
    let directory = URL(fileURLWithPath: path)
    let store = RuntimeFileStore(directory: directory)
    let sut = MonitoringLifecycle(storage: store, driver: MonitoringDriver(
        startFocus: { _ in preconditionFailure("Unexpected focus") },
        startDeadline: { name, _ in
            precondition(!RuntimeLockContext.held)
            try saveInventory(loadInventory(directory) + [name], directory)
            try Data("ready".utf8).write(to: directory.appendingPathComponent("inflight-ready"))
            kill(getpid(), SIGSTOP)
        }, stop: { _ in }, prepareShield: { {} }, clearShield: {},
        activities: { try! loadInventory(directory) }),
        now: { processClock }, configuration: { .default })
    try sut.startDeepFocus(minutes: 60)
}

func runReentrantWorker(directory: String, name: String) throws {
    let store = RuntimeFileStore(directory: URL(fileURLWithPath: directory))
    let sut = MonitoringLifecycle(storage: store, driver: MonitoringDriver(
        startFocus: { _ in preconditionFailure("Callback cannot schedule before commit") },
        startDeadline: { _, _ in preconditionFailure("Callback cannot schedule before commit") },
        stop: { _ in preconditionFailure("Callback cannot stop before commit") },
        prepareShield: { preconditionFailure("No uncommitted shield") }, clearShield: {},
        activities: { preconditionFailure("Callback must return without another Apple call") }),
        now: { processClock }, configuration: { .default })
    try sut.intervalStarted(name: name)
}

@MainActor
func runLockContentionTests() throws {
    do {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BreakLoop-reentrant-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuntimeFileStore(directory: directory)
        var activities: [String] = []
        let sut = MonitoringLifecycle(storage: store, driver: MonitoringDriver(
            startFocus: { snapshot in
                check(!RuntimeLockContext.held, "Cross-process callback is invoked outside real flock")
                let name = MonitoringRuntime.focusName(snapshot.id)
                let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                child.arguments = ["--reentrant-worker", directory.path, name]
                try child.run()
                let limit = Date().addingTimeInterval(5)
                while child.isRunning && Date() < limit { usleep(10_000) }
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                child.waitUntilExit()
                check(child.terminationStatus == 0,
                      "Adversarial Apple stub waits for real child callback, which acquires flock and returns without deadlock")
                activities.append(name)
            }, startDeadline: { _, _ in }, stop: { names in activities.removeAll { names.contains($0) } },
            prepareShield: { {} }, clearShield: {}, activities: { activities }),
            now: { processClock }, configuration: { .default })
        try sut.start()
        let state = try store.readRuntime()
        check(state.snapshot != nil && state.pendingTransition == nil && state.deferredCallbacks == nil && activities.count == 1,
              "Real cross-process reentrancy commits and drains once with no duplicate activity")
    }
    do {
        let h = Harness()
        h.onStart = { name in
            check(!h.store.locked, "Reentrant start callback runs with runtime lock released")
            try! h.sut.intervalStarted(name: name)
            try! h.sut.threshold(name: name, minute: 2)
            check(h.store.state.pendingTransition != nil && h.store.state.snapshot == nil,
                  "Callbacks cannot observe an uncommitted proposed snapshot")
        }
        try h.sut.start()
        check(h.store.state.pendingTransition == nil && h.store.state.checkpoint?.usageMinute == 2,
              "Successful commit replays the durable early threshold exactly once")
        check(h.scheduleAttempts == 1, "Reentrant callback cannot duplicate the in-flight schedule")
    }
    do {
        let h = Harness()
        h.onStart = { name in
            try! h.sut.intervalStarted(name: name)
            check(DashboardState(runtime: h.store.state).mode == .loading,
                  "Pending publication does not expose inactive Start buttons")
        }
        try h.sut.startDeepFocus(minutes: 60)
        check(h.store.state.deepFocus != nil && h.shielded && h.scheduleAttempts == 1,
              "Deep Focus publishes once after reentrant callback returns")
    }
    do {
        let h = Harness()
        h.onScheduleAttempt = { _ in
            h.onScheduleAttempt = nil
            try! h.sut.stop()
        }
        fails { try h.sut.start() }
        check(h.store.state.snapshot == nil && h.store.state.pendingTransition == nil && h.monitored.isEmpty,
              "Stop during start invalidates pending generation even if Apple later returns success")
        check(!h.shielded, "Cancelled normal start cannot apply a delayed shield")
    }
    do {
        let h = Harness(); try h.cooldown()
        let owner = h.store.state.cooldown
        h.onScheduleAttempt = { _ in
            h.onScheduleAttempt = nil
            try! h.sut.stopDeepFocus()
        }
        fails { try h.sut.startDeepFocus(minutes: 60) }
        check(h.store.state.cooldown == owner && h.shielded,
              "Cancelling a Deep Focus launch preserves independent cooldown ownership")
        check(h.store.state.deepFocus == nil && h.monitored.count == 2,
              "Only the cancelled in-flight generation is stopped")
    }
    do {
        let h = Harness(); try h.sut.start()
        let old = h.store.state.snapshot!.id
        h.onStop = { names in
            h.onStop = nil
            try! h.sut.intervalEnded(name: names[0])
            try! h.sut.startDeepFocus(minutes: 60)
        }
        try h.sut.stop()
        check(h.store.state.snapshot == nil && h.store.state.deepFocus != nil && h.shielded,
              "Reentrant Stop callback and newer Deep Focus cannot be overwritten by stale shield clearing")
        check(!h.monitored.contains(MonitoringRuntime.focusName(old)) && h.monitored.count == 1,
              "Old cleanup cannot stop a newer unique generation")
    }
    do {
        let h = Harness()
        h.onStart = { _ in h.store.failedWritesRemaining = 1; h.onStart = nil }
        fails { try h.sut.startDeepFocus(minutes: 60) }
        check(h.store.state.pendingTransition == nil && h.store.state.deepFocus == nil && h.monitored.isEmpty,
              "Failure of final publication after successful Apple scheduling rolls back only the new generation")
        check(!h.shielded, "Final-publication failure cannot introduce a restriction")
    }
    do {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BreakLoop-inflight-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = directory.appendingPathComponent("existing-diagnostic-history.jsonl")
        let historyBytes = Data("preserved history".utf8)
        try historyBytes.write(to: history)
        let store = RuntimeFileStore(directory: directory)
        let cooldown = RestrictionDeadline(endsAt: processClock.addingTimeInterval(1800))
        var original = MonitoringRuntime(); original.cooldown = cooldown
        try store.withRuntimeLock { try store.writeRuntime(original) }
        try saveInventory(original.activityNames, directory)
        let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--inflight-worker", directory.path]
        try child.run()
        defer { if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit() } }
        let ready = directory.appendingPathComponent("inflight-ready")
        let limit = Date().addingTimeInterval(8)
        while !FileManager.default.fileExists(atPath: ready.path), Date() < limit, child.isRunning { usleep(10_000) }
        check(FileManager.default.fileExists(atPath: ready.path), "Real child reached scheduling after durable intent")
        let pending = try store.withRuntimeLock { try store.readRuntime() }
        check(pending.pendingTransition != nil && pending.deepFocus == nil && pending.cooldown == cooldown,
              "Other process can acquire flock during the child's in-flight scheduling and sees only prior committed owners")
        kill(child.processIdentifier, SIGKILL); child.waitUntilExit()
        var shield = true
        let sut = MonitoringLifecycle(storage: store, driver: MonitoringDriver(
            startFocus: { _ in preconditionFailure("No automatic retry") },
            startDeadline: { _, _ in preconditionFailure("No automatic retry") },
            stop: { names in
                check(!RuntimeLockContext.held, "Crash recovery stop executes without runtime flock")
                try! saveInventory(loadInventory(directory).filter { !names.contains($0) }, directory)
            }, prepareShield: { { shield = true } }, clearShield: { shield = false },
            activities: {
                check(!RuntimeLockContext.held, "Crash recovery inventory executes without runtime flock")
                return try! loadInventory(directory)
            }), now: { processClock }, configuration: { .default })
        try sut.reconcile()
        let recovered = try store.readRuntime()
        check(recovered.pendingTransition == nil && recovered.deepFocus == nil && recovered.cooldown == cooldown,
              "SIGKILL recovery does not publish the unfinished Deep Focus or discard the independent cooldown")
        check(try loadInventory(directory) == original.activityNames && shield,
              "SIGKILL recovery removes only orphan generation and preserves existing shield ownership")
        check(try Data(contentsOf: history) == historyBytes, "Crash recovery preserves prior diagnostic history")
    }
    do {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BreakLoop-timing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = PersistentLogStore(directory: directory)
        let log = AppLogger(persistentStore: archive)
        let value = log.timed("device_start", metadata: ["applicationTokens": "4", "tokenIdentity": "SECRET"]) { 42 }
        _ = archive.flush()
        let entries = archive.history().events.filter { $0.event.hasPrefix("device_start_") }
        check(value == 42 && entries.count == 2, "Timing instrumentation preserves result and archives paired start/end")
        check(entries[0].metadata["spanId"] == entries[1].metadata["spanId"] && entries[1].metadata["durationMs"] != nil,
              "Span identity and monotonic duration survive privacy filtering")
        check(entries[0].metadata["processID"] != nil && entries[0].metadata["threadID"] != nil && entries[0].metadata["runtimeLockHeld"] == "false",
              "Process/thread/lock state survive export without token identities")
        check(entries.allSatisfy { $0.metadata["tokenIdentity"] == nil }, "Timing does not widen the token-identity privacy boundary")
    }
    do {
        for configured in [false, true] {
            check(AuthorizationStartupPolicy.route(sample: .undetermined, configured: configured, settled: false) == .checking,
                  "Initial Not Determined shows checking, never an immediate permission screen")
            check(AuthorizationStartupPolicy.route(sample: .approved, configured: configured, settled: false) == .authorized,
                  "Approved exits checking immediately")
            check(AuthorizationStartupPolicy.route(sample: .denied, configured: configured, settled: false) == .permissionRequired,
                  "Denied remains a real permission-required state")
        }
        check(AuthorizationStartupPolicy.route(sample: .undetermined, configured: true, settled: true) == .permissionRequired,
              "Persistent unapproved sample eventually exposes a bounded recovery screen")
        check(AuthorizationStartupPolicy.route(sample: .undetermined, configured: false, settled: true) == .onboarding,
              "Genuine first-time setup remains available after bounded settlement")
        check(!AuthorizationStartupPolicy.provesRevocation(previouslyApproved: true, sample: .undetermined),
              "Transient Not Determined cannot trigger destructive revocation cleanup")
        check(!AuthorizationStartupPolicy.provesRevocation(previouslyApproved: true, sample: .unknown),
              "Unknown framework status is not proof of revocation")
        check(AuthorizationStartupPolicy.provesRevocation(previouslyApproved: true, sample: .denied),
              "Actual transition from Approved to Denied retains revocation handling")
    }
}
