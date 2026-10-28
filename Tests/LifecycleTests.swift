import Foundation

// Compile with the real production lifecycle, domain models and calculators (see run-regressions.sh).
enum InjectedFailure: Error { case scheduling, persistence }
final class MemoryStore: MonitoringRuntimeStore {
    var state = MonitoringRuntime()
    var failWrite = false
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
        self.state = state
    }
}
final class Harness {
    let store = MemoryStore()
    var time = Date(timeIntervalSince1970: 1_800_000_000)
    var failSchedule = false
    var monitored: [String] = []
    var shielded = false
    var rejected: [String] = []
    var config = CycleConfiguration.default
    var onStart: ((String) -> Void)?
    lazy var sut = MonitoringLifecycle(storage: store, driver: MonitoringDriver(
        startFocus: { [unowned self] snapshot in try schedule(MonitoringRuntime.focusName(snapshot.id)) },
        startDeadline: { [unowned self] name, _ in try schedule(name) },
        stop: { [unowned self] names in monitored.removeAll { names.contains($0) } },
        shield: { [unowned self] in shielded = $0 },
        activities: { [unowned self] in monitored }),
        now: { [unowned self] in time }, configuration: { [unowned self] in config },
        log: { [unowned self] event, _ in rejected.append(event) })
    func schedule(_ name: String) throws {
        precondition(store.locked, "Scheduling must hold the shared lock")
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
    static func main() throws {
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
        print("Lifecycle regressions: \(count) checks passed")
    }
}
