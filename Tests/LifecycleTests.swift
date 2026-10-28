import Foundation

// Compile with the real production lifecycle, domain models and calculators (see run-regressions.sh).
enum InjectedFailure: Error { case scheduling, persistence }
final class MemoryStore: MonitoringRuntimeStore {
    var state = MonitoringRuntime()
    var failWrite = false
    var failedWritesRemaining = 0
    var locked = false
    var afterUnlock: (() -> Void)?
    func withRuntimeLock<T>(_ body: () throws -> T) throws -> T {
        precondition(!locked)
        locked = true
        defer { locked = false; let callback = afterUnlock; afterUnlock = nil; callback?() }
        return try body()
    }
    func readRuntime() throws -> MonitoringRuntime { state }
    func writeRuntime(_ state: MonitoringRuntime) throws {
        precondition(locked)
        if failWrite { throw InjectedFailure.persistence }
        if failedWritesRemaining > 0 { failedWritesRemaining -= 1; throw InjectedFailure.persistence }
        self.state = state
    }
}
struct TestSelection: Codable {
    var applications = 1
    var categories = 0
    var webDomains = 0
}
final class Harness {
    let store = MemoryStore()
    var time = Date(timeIntervalSince1970: 1_800_000_000)
    var failSchedule = false
    var scheduleAttempts = 0
    var monitored: [String] = []
    var shielded = false
    var rejected: [String] = []
    var diagnostics: [[String: String]] = []
    var config = CycleConfiguration.default
    var onStart: ((String) -> Void)?
    var onScheduleAttempt: ((String) -> Void)?
    var selectionData: Data? = try! JSONEncoder().encode(TestSelection())
    var selectionReadError: Error?
    var shieldWrites = 0
    var clears = 0
    var selectionReads = 0
    var selectionCountReports: [[String: String]] = []
    var selectionLoader: ShieldSelectionLoader<TestSelection> {
        ShieldSelectionLoader(load: { [unowned self] in
            selectionReads += 1
            if let selectionReadError { throw selectionReadError }
            return try selectionData.map { try JSONDecoder().decode(TestSelection.self, from: $0) }
        }, supported: {
            ShieldSelectionSupport.isSupported(applications: $0.applications, categories: $0.categories, webDomains: $0.webDomains)
        }, apply: { [unowned self] _ in shielded = true; shieldWrites += 1 },
        inspected: { [unowned self] selection, accepted in
            selectionCountReports.append(SelectionTokenCounts(applicationTokens: selection.applications,
                categoryTokens: selection.categories, webDomainTokens: selection.webDomains).diagnosticCounts
                .merging(["result": accepted ? "accepted" : "rejected"]) { existing, _ in existing })
        })
    }
    lazy var sut = MonitoringLifecycle(storage: store, driver: MonitoringDriver(
        startFocus: { [unowned self] snapshot in
            _ = try selectionLoader.selection()
            try schedule(MonitoringRuntime.focusName(snapshot.id))
        },
        startDeadline: { [unowned self] name, _ in try schedule(name) },
        stop: { [unowned self] names in monitored.removeAll { names.contains($0) } },
        prepareShield: { [unowned self] in try selectionLoader.prepare() },
        clearShield: { [unowned self] in shielded = false; clears += 1 },
        activities: { [unowned self] in monitored }),
        now: { [unowned self] in time }, configuration: { [unowned self] in config },
        log: { [unowned self] event, _, metadata in rejected.append(event); diagnostics.append(metadata) })
    func schedule(_ name: String) throws {
        precondition(store.locked, "Scheduling must hold the shared lock")
        scheduleAttempts += 1
        onScheduleAttempt?(name)
        if failSchedule { throw InjectedFailure.scheduling }
        monitored.append(name)
        onStart?(name)
    }
    func cooldown() throws {
        try sut.start()
        try sut.threshold(name: MonitoringRuntime.focusName(store.state.snapshot!.id), minute: nil)
    }
}
var count = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) {
    let result = try! value()
    precondition(result, message); count += 1
}
func fails(_ action: () throws -> Void) { do { try action(); preconditionFailure("Expected failure") } catch { count += 1 } }

@main struct LifecycleTests {
    @MainActor static func main() throws {
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--post-runtime-change" {
            guard RuntimeChangeSignal.post() == 0 else { exit(1) }
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--increment" {
            let store = RuntimeFileStore(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            for _ in 0..<30 {
                try store.withRuntimeLock {
                    var state = try store.readRuntime()
                    state.checkpoint = UsageCheckpointState(usageMinute: (state.checkpoint?.usageMinute ?? 0) + 1, timestamp: Date())
                    try store.writeRuntime(state)
                }
            }
            return
        }
        do {
            let h = Harness(); h.failSchedule = true
            fails { try h.sut.start() }
            check(h.store.state.snapshot == nil && h.monitored.isEmpty && !h.shielded, "Failed start is inactive")
        }
        do {
            let h = Harness(); h.store.failWrite = true
            fails { try h.sut.start() }
            check(h.store.state == MonitoringRuntime() && h.monitored.isEmpty, "Failed atomic commit removes new schedule")
        }
        do {
            let h = Harness(); try h.sut.start(); let original = h.store.state
            h.failSchedule = true; try h.sut.start()
            check(h.store.state == original, "Repeated Start preserves valid session")
            h.store.failWrite = true; fails { try h.sut.stop() }
            check(h.store.state == original && !h.monitored.isEmpty, "Failed stop preserves coherent prior session")
        }
        do {
            let h = Harness()
            h.onStart = { name in
                // Models an immediate extension callback waiting on the production cross-process lock.
                h.store.afterUnlock = { try! h.sut.threshold(name: name, minute: 2) }
            }
            try h.sut.start()
            check(h.store.state.checkpoint?.usageMinute == 2, "Immediate callback observes committed snapshot")
        }
        do {
            let h = Harness(); h.store.failWrite = true
            h.onStart = { name in h.store.afterUnlock = { try! h.sut.threshold(name: name, minute: nil) } }
            fails { try h.sut.start() }
            check(h.store.state.snapshot == nil && !h.shielded, "Immediate callback after failed commit is rejected")
        }
        do {
            let h = Harness(); try h.sut.start(); h.monitored = []; h.failSchedule = true
            fails { try h.sut.reconcile() }
            check(h.store.state.snapshot == nil, "Failed recovery of missing monitor clears phantom active state")
        }
        do {
            let h = Harness(); try h.cooldown(); let before = h.store.state
            let names = h.monitored
            h.failSchedule = true; fails { try h.sut.extendCooldown(minutes: 15) }
            check(h.store.state == before && h.monitored == names && h.shielded, "Failed extension preserves old deadline and shield")
            h.failSchedule = false; h.store.failWrite = true
            fails { try h.sut.extendCooldown(minutes: 15) }
            check(h.store.state == before && h.monitored == names, "Failed reschedule persistence preserves old schedule")
            h.store.failWrite = false; try h.sut.extendCooldown(minutes: 15)
            check(h.store.state.cooldown!.endsAt == before.cooldown!.endsAt.addingTimeInterval(900), "Extension commits intended deadline")
            check(h.store.state.cooldown!.id != before.cooldown!.id, "Extension rotates generation")
            h.time = before.cooldown!.endsAt
            try h.sut.intervalEnded(name: MonitoringRuntime.cooldownName(before.cooldown!.id))
            check(h.shielded && h.store.state.cooldown != nil, "Old end cannot release extended cooldown")
            try h.sut.intervalEnded(name: h.store.state.cooldownName!)
            check(h.shielded, "Early callback for current generation cannot release shield")
            h.time = h.store.state.cooldown!.endsAt
            try h.sut.intervalEnded(name: h.store.state.cooldownName!)
            check(!h.shielded && h.store.state.snapshot!.id != before.snapshot!.id, "Completion releases and starts fresh cycle")
        }
        do {
            let h = Harness(); try h.cooldown(); let before = h.store.state
            h.failSchedule = true; fails { try h.sut.startDeepFocus(minutes: 60) }
            check(h.store.state == before && h.shielded, "Deep Focus failure preserves cooldown owner")
            h.failSchedule = false; h.store.failWrite = true
            fails { try h.sut.startDeepFocus(minutes: 60) }
            check(h.store.state == before && h.monitored.count == 2, "Deep Focus persistence failure removes only new activity")
            h.store.failWrite = false; try h.sut.startDeepFocus(minutes: 60)
            let oldSession = h.store.state.deepFocus!
            try h.sut.stopDeepFocus()
            check(h.shielded && h.store.state.cooldown == before.cooldown, "Early termination retains cooldown")
            try h.sut.startDeepFocus(minutes: 120)
            h.time = oldSession.endsAt
            try h.sut.intervalEnded(name: MonitoringRuntime.deepFocusName(oldSession.id))
            check(h.shielded && h.store.state.deepFocus != nil, "Old Deep Focus end cannot release replacement")
            try h.sut.reconcile()
            check(h.store.state.cooldown == nil && h.shielded, "Expired cooldown retains Deep Focus shield")
            h.time = h.store.state.deepFocus!.endsAt; try h.sut.reconcile()
            check(!h.shielded && h.store.state.deepFocus == nil, "Missing Deep Focus callback reconciles")
        }
        do {
            let h = Harness(); h.failSchedule = true
            fails { try h.sut.startDeepFocus(minutes: 60) }
            check(h.store.state.deepFocus == nil && !h.shielded, "Standalone failed Deep Focus creates no shield")
        }
        do {
            let h = Harness(); try h.cooldown(); try h.sut.startDeepFocus(minutes: 60)
            let old = h.store.state
            try h.sut.stop()
            check(h.shielded && h.store.state.deepFocus == old.deepFocus, "Stop BreakLoop retains Deep Focus owner")
            try h.sut.start(); let fresh = h.store.state
            try h.sut.threshold(name: MonitoringRuntime.focusName(old.snapshot!.id), minute: nil)
            try h.sut.intervalEnded(name: old.cooldownName!)
            try h.sut.intervalStarted(name: MonitoringRuntime.focusName(old.snapshot!.id))
            check(h.store.state == fresh, "Stop/restart rejects old thresholds and interval callbacks")
            try h.sut.stop(all: true)
            try h.sut.threshold(name: MonitoringRuntime.focusName(fresh.snapshot!.id), minute: nil)
            check(h.store.state.snapshot == nil && !h.shielded, "Threshold after Stop cannot reactivate")
            check(h.rejected.contains("stale_threshold_rejected"), "Stale callback rejection logged")
        }
        do {
            let h = Harness(); try h.cooldown(); h.time = h.store.state.cooldown!.endsAt
            h.failSchedule = true; fails { try h.sut.reconcile() }
            check(h.store.state.snapshot == nil && h.store.state.cooldown == nil && !h.shielded,
                  "Restart failure after expired cooldown cannot strand shield or phantom active state")
        }
        do {
            let h = Harness(); try h.sut.start()
            let name = MonitoringRuntime.focusName(h.store.state.snapshot!.id)
            try h.sut.threshold(name: name, minute: 2)
            h.time = h.time.addingTimeInterval(17 * 60)
            h.config = CycleConfiguration(usageLimitMinutes: 40, restDurationMinutes: 20)
            try h.sut.threshold(name: name, minute: 4)
            check(h.store.state.snapshot!.usageLimitMinutes == 40 && !h.shielded, "Natural rest starts fresh budget with latest configuration")
            let fresh = h.store.state
            try h.sut.threshold(name: name, minute: nil)
            check(h.store.state == fresh, "Natural rest rotates callback identity")
        }
        do {
            let h = Harness(); h.store.state.cooldown = RestrictionDeadline(endsAt: h.time.addingTimeInterval(60))
            h.store.state.legacyCooldown = true; h.monitored = ["breakloop.cooldown"]
            try h.sut.reconcile()
            check(h.monitored.contains("breakloop.cooldown") && h.shielded, "Upgrade retains legacy deadline monitoring")
            h.time = h.time.addingTimeInterval(60)
            try h.sut.intervalEnded(name: "breakloop.cooldown")
            check(!h.shielded && h.store.state.cooldown == nil, "Legacy deadline completion remains valid")
        }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let first = RuntimeFileStore(directory: directory)
            let second = RuntimeFileStore(directory: directory)
            var expected = MonitoringRuntime()
            expected.snapshot = CycleSnapshot(configuration: .default)
            try first.withRuntimeLock { try first.writeRuntime(expected) }
            check(try second.readRuntime() == expected, "Separate storage instances read the atomic production record")
            let processes = (0..<2).map { _ -> Process in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                process.arguments = ["--increment", directory.path]
                return process
            }
            for process in processes { try process.run() }
            for process in processes { process.waitUntilExit(); check(process.terminationStatus == 0, "Storage worker succeeded") }
            check(try second.readRuntime().checkpoint?.usageMinute == 60, "Production file lock serializes independent processes")
            // Restore the baseline for the I/O fault check below.
            try first.withRuntimeLock { try first.writeRuntime(expected) }
            let original = try Data(contentsOf: first.recordURL)
            // A directory at the destination makes atomic replacement fail deterministically.
            try FileManager.default.removeItem(at: first.recordURL)
            try FileManager.default.createDirectory(at: first.recordURL, withIntermediateDirectories: false)
            fails { try first.withRuntimeLock { try first.writeRuntime(MonitoringRuntime()) } }
            try FileManager.default.removeItem(at: first.recordURL)
            try original.write(to: first.recordURL)
            check(try second.readRuntime() == expected, "Storage read remains coherent after injected I/O failure")
            try Data("corrupt".utf8).write(to: first.recordURL)
            fails { _ = try first.readRuntime() }
        }
        do {
            let formatter = ISO8601DateFormatter()
            for text in ["2026-12-31T23:55:00Z", "2026-03-08T06:55:00Z", "2026-11-01T05:55:00Z"] {
                let start = formatter.date(from: text)!
                let end = start.addingTimeInterval(1800)
                let plan = try DeadlineSchedulePlan(end: end, now: start)
                check(plan.startComponents.calendar!.date(from: plan.startComponents) == start, "Explicit calendar reconstructs start across midnight/DST")
                check(plan.endComponents.calendar!.date(from: plan.endComponents) == end, "Explicit calendar reconstructs deadline across midnight/DST")
                try plan.validate(DateInterval(start: start, end: end))
                fails { try plan.validate(nil) }
                fails { try plan.validate(DateInterval(start: start, end: end.addingTimeInterval(3600))) }
                fails { try plan.validate(DateInterval(start: start.addingTimeInterval(3600), end: end.addingTimeInterval(3600))) }
            }
            fails { _ = try DeadlineSchedulePlan(end: Date(), now: Date()) }
        }
        do {
            let h = Harness(); h.time = h.time.addingTimeInterval(0.75)
            try h.sut.startDeepFocus(minutes: 15)
            let session = h.store.state.deepFocus!
            check(session.endsAt.timeIntervalSince1970.rounded() == session.endsAt.timeIntervalSince1970,
                  "Persisted deadline aligns exactly with schedule seconds")
            try h.sut.intervalEnded(name: h.store.state.deepFocusName!)
            check(h.shielded && h.store.state.deepFocus != nil, "Early Deep Focus end retains its shield")
            h.time = session.endsAt
            try h.sut.intervalEnded(name: h.store.state.deepFocusName!)
            check(!h.shielded && h.store.state.deepFocus == nil, "Standalone Deep Focus completes successfully")
            fails { try h.sut.startDeepFocus(minutes: 0) }
        }
        precondition(count == 68, "All original 68 lifecycle checks executed")
        let legacyCount = count
        try hardeningTests()
        print("Lifecycle regressions: \(count) checks passed (original \(legacyCount) plus \(count - legacyCount) hardening)")
        let beforeDashboardTests = count
        try runDashboardSynchronizationTests()
        print("Dashboard synchronization: \(count - beforeDashboardTests) checks passed")
        let beforeSelectionTests = count
        try runCooldownSelectionRegressionTests()
        print("Cooldown/selection regressions: \(count - beforeSelectionTests) checks passed")
    }
}


func hardeningTests() throws {
    do {
        let h = Harness(); try h.cooldown(); let before = h.store.state
        h.monitored.removeAll { $0 == MonitoringRuntime.focusName(before.snapshot!.id) }
        fails { try h.sut.reconcile() }
        check(h.store.state.snapshot == nil && h.store.state.cooldown == before.cooldown && h.shielded,
              "Missing focus recovery preserves previously valid cooldown owner")
        check(h.monitored == [before.cooldownName!], "Valid cooldown schedule survives normal interruption")
    }
    do {
        let h = Harness()
        h.store.state.snapshot = CycleSnapshot(configuration: .default)
        h.store.state.legacyFocus = true; h.monitored = ["breakloop.focus"]
        try h.sut.reconcile()
        check(h.store.state.snapshot != nil && h.store.state.legacyFocus == nil,
              "Legacy focus still migrates to a generation-aware activity")
        check(!h.monitored.contains("breakloop.focus") && h.monitored.count == 1, "Migration replaces only the legacy activity")
    }
    do {
        let h = Harness(); try h.sut.start()
        let focus = MonitoringRuntime.focusName(h.store.state.snapshot!.id)
        h.onStart = { name in h.store.afterUnlock = { try! h.sut.intervalStarted(name: name) } }
        try h.sut.threshold(name: focus, minute: nil)
        check(h.store.state.cooldown != nil && h.monitored.count == 2 && h.shielded,
              "Immediate successful cooldown callback sees fully committed state without duplicate activities")
    }
    for code in [MonitoringFailureCode.selectionMissing, .selectionCorrupted, .selectionUnsupported, .selectionUnavailable] {
        let h = Harness()
        switch code {
        case .selectionMissing: h.selectionData = nil
        case .selectionCorrupted: h.selectionData = Data("invalid json".utf8)
        case .selectionUnsupported: h.selectionData = try JSONEncoder().encode(TestSelection(applications: 0))
        default: h.selectionReadError = InjectedFailure.persistence
        }
        fails { try h.sut.startDeepFocus(minutes: 60) }
        check(h.store.state.deepFocus == nil && h.monitored.isEmpty && h.shieldWrites == 0,
              "Invalid selection cannot publish or apply a new restriction")
        check(h.store.state.attention?.code == code, "Missing/corrupt/unsupported/persistence selection failures are distinct")
        check(h.store.state.attention?.resolvedAt == nil, "Selection failure needs attention")
        try h.sut.reconcile()
        check(h.store.state.attention?.code == code, "Extension selection error remains discoverable on foreground")
    }
    do {
        check(!ShieldSelectionSupport.isSupported(applications: 0, categories: 0, webDomains: 1), "Web-only selection unsupported")
        check(!ShieldSelectionSupport.isSupported(applications: 1, categories: 0, webDomains: 1), "Mixed unsupported website selection rejected")
        check(!ShieldSelectionSupport.isSupported(applications: 0, categories: 51, webDomains: 0), "Unsupported category count rejected")
        check(!ShieldSelectionSupport.isSupported(applications: 51, categories: 0, webDomains: 0), "Unsupported application count rejected")
        check(ShieldSelectionSupport.isSupported(applications: 50, categories: 50, webDomains: 0), "Supported application and category limits accepted")
        check(ShieldSelectionSupport.isSupported(applications: 0, categories: 50, webDomains: 0), "Supported category boundary accepted")
        let h = Harness()
        let prepared = try h.selectionLoader.prepare()
        h.selectionData = nil
        prepared()
        check(h.shielded && h.selectionReads == 1, "Prepared adapter captures validated selection without a post-commit reload")
    }
    do {
        let h = Harness(); try h.cooldown()
        let before = h.store.state; let monitored = h.monitored; let clears = h.clears
        h.selectionData = nil
        fails { try h.sut.startDeepFocus(minutes: 60) }
        check(h.store.state.cooldown == before.cooldown && h.store.state.deepFocus == nil,
              "Failed Deep Focus preflight retains valid cooldown ownership")
        check(h.shielded && h.monitored == monitored && h.clears == clears,
              "Selection failure never clears an existing cooldown shield or schedule")
        fails { try h.sut.reconcile() }
        check(h.shielded && h.clears == clears, "Reconcile reports selection failure without clearing valid owner")
        h.selectionData = try JSONEncoder().encode(TestSelection())
        try h.sut.reconcile()
        check(h.shielded && h.monitored == monitored, "Selection restoration reapplies without duplicate monitoring")
        check(h.store.state.attention?.resolvedAt != nil, "Recovered failure remains discoverable with resolved status")
        h.time = h.store.state.cooldown!.endsAt; h.selectionData = nil
        fails { try h.sut.reconcile() }
        check(!h.shielded && h.store.state.cooldown == nil, "Expired owner cleanup does not require loading selection")
    }
    do {
        let h = Harness(); try h.cooldown(); try h.sut.startDeepFocus(minutes: 60)
        let before = h.store.state; let names = h.monitored; let clears = h.clears
        h.selectionData = Data("corrupt".utf8)
        fails { try h.sut.reconcile() }
        check(h.store.state.cooldown == before.cooldown && h.store.state.deepFocus == before.deepFocus,
              "Corrupt selection preserves overlapping owners")
        check(h.shielded && h.monitored == names && h.clears == clears, "Overlap failure retains prior shield and both schedules")
        h.time = h.store.state.cooldown!.endsAt
        fails { try h.sut.reconcile() }
        check(h.store.state.cooldown == nil && h.store.state.deepFocus == before.deepFocus && h.shielded,
              "Expired cooldown removed while valid Deep Focus remains after selection failure")
        check(h.store.state.snapshot == nil, "A fresh cycle is never published if its selection preflight failed")
        h.selectionData = try JSONEncoder().encode(TestSelection())
        try h.sut.reconcile()
        check(h.monitored == [MonitoringRuntime.deepFocusName(before.deepFocus!.id)], "Restored selection introduces no duplicate generations")
        h.time = before.deepFocus!.endsAt; h.selectionData = nil
        try h.sut.reconcile()
        check(h.store.state.deepFocus == nil && !h.shielded, "Last expired owner clears despite previous selection failure")
    }
    do {
        let h = Harness(); try h.sut.start()
        let focus = MonitoringRuntime.focusName(h.store.state.snapshot!.id)
        h.failSchedule = true
        do { try h.sut.threshold(name: focus, minute: nil); preconditionFailure("Expected interruption") }
        catch { check(error as? InjectedFailure == .scheduling, "Original scheduling error preserved") }
        check(h.store.state.snapshot == nil && h.store.state.cooldown == nil && h.store.state.checkpoint == nil,
              "Final scheduling failure invalidates spent normal generation")
        check(!h.shielded && h.monitored.isEmpty, "No cooldown shield or phantom active activity after scheduling failure")
        check(h.store.state.attention?.code == .cooldownScheduling, "Scheduling interruption is persisted")
        check(h.diagnostics.contains { $0["failureCode"] == "cooldownScheduling" && $0["activity"] == focus },
              "Structured diagnostics include original failure code and affected generation")
        let interrupted = h.store.state
        try h.sut.threshold(name: focus, minute: nil)
        check(h.store.state == interrupted, "Stale threshold cannot retry interrupted cycle")
        h.failSchedule = false; try h.sut.reconcile()
        check(h.store.state.snapshot == nil && h.monitored.isEmpty, "Foreground never silently restarts interrupted cycle")
        check(h.store.state.attention?.code == .cooldownScheduling, "Foreground exposes original scheduling error")
        try h.sut.start()
        check(h.store.state.snapshot != nil && h.store.state.attention == nil, "Explicit restart clears interruption after successful commit")
        check(!h.monitored.contains(focus), "Restart uses a new UUID")
    }
    do {
        let h = Harness(); try h.sut.start(); try h.sut.startDeepFocus(minutes: 60)
        let session = h.store.state.deepFocus!
        let focus = MonitoringRuntime.focusName(h.store.state.snapshot!.id)
        h.failSchedule = true
        fails { try h.sut.threshold(name: focus, minute: nil) }
        check(h.store.state.deepFocus == session && h.shielded, "Cooldown failure preserves independently valid Deep Focus")
        check(h.monitored == [MonitoringRuntime.deepFocusName(session.id)], "Only affected focus monitoring is stopped")
    }
    do {
        let h = Harness(); try h.sut.start(); try h.sut.startDeepFocus(minutes: 60)
        let focus = MonitoringRuntime.focusName(h.store.state.snapshot!.id)
        h.failSchedule = true; h.store.failWrite = true
        do { try h.sut.threshold(name: focus, minute: nil); preconditionFailure("Expected recovery write failure") }
        catch let error as MonitoringRecoveryError {
            check(error.original as? InjectedFailure == .scheduling, "Recovery write failure retains original scheduling error")
            check(error.persistence as? InjectedFailure == .persistence, "Recovery persistence failure is separately reported")
        }
        check(h.store.state.snapshot != nil && h.store.state.attention == nil, "Unavailable store does not falsely claim interruption was persisted")
        check(h.diagnostics.contains { $0["safeStatePersisted"] == "false" }, "Persistence failure is explicitly logged as uncommitted")
        check(!h.monitored.contains(focus) && h.shielded, "Focus stopped even when recovery write fails; Deep Focus shield retained")
        try h.sut.threshold(name: focus, minute: nil)
        check(h.rejected.last == "stale_threshold_rejected", "Inventory rejects stopped generation despite stale persisted snapshot")
        h.store.failWrite = false; h.failSchedule = false
        fails { try h.sut.reconcile() }
        check(h.store.state.snapshot == nil && h.store.state.attention?.code == .monitorUnavailable,
              "Foreground persists interruption after storage restoration, without blind restart")
        check(h.store.state.deepFocus != nil && h.shielded, "Failure recovery preserves Deep Focus ownership")
        try h.sut.start()
        check(h.store.state.snapshot != nil && h.store.state.attention == nil, "Explicit restart works after recovered storage")
    }
    do {
        let h = Harness(); try h.sut.start()
        let focus = MonitoringRuntime.focusName(h.store.state.snapshot!.id)
        h.store.failedWritesRemaining = 1 // schedule succeeds, publishing cooldown fails, recovery write succeeds
        fails { try h.sut.threshold(name: focus, minute: nil) }
        check(h.store.state.attention?.code == .runtimePersistence, "Failed cooldown publication distinguished from failed scheduling")
        check(h.store.state.snapshot == nil && h.monitored.isEmpty && !h.shielded,
              "Failed publication stops uncommitted deadline and interrupts focus")
    }
    do {
        let h = Harness(); try h.sut.start()
        let focus = MonitoringRuntime.focusName(h.store.state.snapshot!.id)
        h.onScheduleAttempt = { _ in
            h.store.afterUnlock = { try! h.sut.threshold(name: focus, minute: nil) }
        }
        h.failSchedule = true
        fails { try h.sut.threshold(name: focus, minute: nil) }
        check(h.store.state.snapshot == nil && h.rejected.contains("stale_threshold_rejected"),
              "Immediate callback waits for interruption and cannot retry failed scheduling")
    }
    do {
        let h = Harness(); try h.sut.start()
        let focus = MonitoringRuntime.focusName(h.store.state.snapshot!.id)
        h.selectionData = nil
        fails { try h.sut.threshold(name: focus, minute: nil) }
        check(h.store.state.snapshot == nil && h.store.state.attention?.code == .selectionMissing && !h.shielded,
              "Selection preflight failure at final threshold also interrupts normal monitoring")
        h.selectionData = try JSONEncoder().encode(TestSelection())
        try h.sut.start()
        check(h.store.state.snapshot != nil, "Cycle can restart after selection restoration")
    }
    do {
        let h = Harness(); h.selectionData = nil; h.store.failWrite = true
        do { try h.sut.startDeepFocus(minutes: 60); preconditionFailure("Expected combined failure") }
        catch let error as MonitoringRecoveryError {
            check(SelectionFailure.classify(error.original) == .selectionMissing, "Selection and attention persistence failure both retained")
        }
        check(h.store.state.deepFocus == nil && !h.shielded, "Failed attention write cannot publish a restriction")
    }
    do {
        let h = Harness(); try h.sut.start()
        let oldID = h.store.state.snapshot!.id
        h.failSchedule = true; h.store.failWrite = true
        fails { try h.sut.threshold(name: MonitoringRuntime.focusName(oldID), minute: nil) }
        h.failSchedule = false; h.store.failWrite = false
        try h.sut.start()
        check(h.store.state.snapshot?.id != oldID && h.monitored.count == 1,
              "Explicit Start can directly recover a stopped generation after storage is restored")
    }
    do {
        let oldJSON = Data("{}".utf8)
        let runtime = try JSONDecoder().decode(MonitoringRuntime.self, from: oldJSON)
        check(runtime.attention == nil && runtime.legacyFocus == nil, "Old runtime JSON remains decodable")
        let h = Harness(); try h.sut.start(); h.failSchedule = true
        fails { try h.sut.threshold(name: MonitoringRuntime.focusName(h.store.state.snapshot!.id), minute: nil) }
        let encoded = try JSONEncoder().encode(h.store.state)
        check(try JSONDecoder().decode(MonitoringRuntime.self, from: encoded) == h.store.state,
              "Attention survives JSON persistence and relaunch")
    }
}
