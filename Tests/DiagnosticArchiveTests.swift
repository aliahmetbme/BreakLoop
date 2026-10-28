import Foundation
import Darwin

private func event(_ date: Date, index: Int = 0, level: LogLevel = .info, operation: UUID = UUID()) -> LogEntry {
    LogEntry(id: UUID(), timestamp: date, level: level, category: .monitoring,
        event: "test_transition", message: "secret application and private web content",
        metadata: ["usageMinute": "\(index)", "rawToken": "SECRET-TOKEN", "website": "private.example", "applicationTokens": "4"],
        process: "com.aliahmeterdogdu.BreakLoop", processInstanceID: UUID(), operationID: operation,
        outcome: "succeeded", appVersion: "1.0", appBuild: "10")
}
private func temporaryArchive() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("BreakLoop-diagnostic-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private func archiveBytes(_ root: URL) throws -> Data {
    let folder = root.appendingPathComponent("Diagnostics-v1")
    var data = Data()
    for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
        data.append(try Data(contentsOf: file))
    }
    return data
}
func diagnosticWorker(directory: String, index: Int) throws {
    var config = DiagnosticArchiveConfiguration(); config.segmentBytes = 1024; config.lockTimeout = 2
    let store = PersistentLogStore(directory: URL(fileURLWithPath: directory), configuration: config)
    for value in 0..<60 { store.append(event(Date(), index: index * 1000 + value)) }
    guard store.flush(timeout: 30), store.history(limit: 1000).error == nil else { throw InjectedFailure.persistence }
}
@MainActor
func runDiagnosticArchiveTests() throws {
    let clock = ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z")!
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentLogStore(directory: root, now: { clock })
        for day in 0..<17 { store.append(event(clock.addingTimeInterval(-Double(day) * 86400), index: day)) }
        check(store.flush(), "Daily archive flush completes")
        let result = store.history(limit: 1000)
        check(result.events.count == 15, "Fourteen full days plus current UTC partial day retained at boundary")
        check(result.events.contains { $0.metadata["usageMinute"] == "8" }, "Failure sequence from more than one week ago is retained")
        check(!result.events.contains { $0.metadata["usageMinute"] == "15" }, "Events older than retained UTC day boundary expire")
        check(result.oldest != nil && result.newest == clock && result.earlyEvictionAt == nil, "Available history dates are accurate without pressure")
        let reinstalled = PersistentLogStore(directory: root, now: { clock })
        check(reinstalled.history(limit: 1000).events.count == 15, "In-place app update/restart preserves archive")
        let raw = String(decoding: try archiveBytes(root), as: UTF8.self)
        check(!raw.contains("SECRET-TOKEN") && !raw.contains("private.example") && !raw.contains("private web content"), "Persisted archive contains no token/website/free-form content")
        let output = root.appendingPathComponent("export.jsonl")
        try store.export(filter: DiagnosticFilter(start: clock.addingTimeInterval(-9 * 86400), end: clock.addingTimeInterval(-7 * 86400)), destination: output)
        let lines = try String(contentsOf: output, encoding: .utf8).split(separator: "\n")
        check(lines.count == 4 && lines.first!.contains("breakloop_diagnostic_manifest"), "Historical date-range export includes manifest and three matching days")
        check(!String(lines.joined()).contains("SECRET-TOKEN"), "Exports apply the same privacy boundary")
        check(result.events.map(\.timestamp) == result.events.map(\.timestamp).sorted(), "Timeline ordering is chronological")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        var config = DiagnosticArchiveConfiguration(); config.maximumBytes = 16 * 1024; config.segmentBytes = 1024
        let store = PersistentLogStore(directory: root, configuration: config, now: { clock })
        for index in 0..<200 { store.append(event(clock, index: index)) }
        check(store.flush(timeout: 10), "Heavy event volume completes on archive worker")
        let result = store.history(limit: 1000)
        check(result.bytes <= config.maximumBytes - 4096, "Archive segments obey explicit byte budget")
        check(result.earlyEvictionAt != nil && result.oldest != nil, "Early history eviction is durable and visible")
        check(result.events.count < 200 && result.events.count > 0, "Heavy volume retains bounded recent events")
        let reopened = PersistentLogStore(directory: root, configuration: config, now: { clock })
        check(reopened.history().earlyEvictionAt != nil, "Storage pressure warning survives an app update")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let workers = (0..<4).map { index -> Process in
            let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--diagnostic-writer", root.path, "\(index)"]; return process
        }
        for worker in workers { try worker.run() }
        for worker in workers { worker.waitUntilExit(); check(worker.terminationStatus == 0, "Concurrent process archive writer succeeds") }
        let store = PersistentLogStore(directory: root)
        let result = store.history(limit: 1000)
        check(result.events.count == 240 && Set(result.events.map(\.id)).count == 240, "Concurrent app/extension-style writes retain every unique event")
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Diagnostics-v1"), includingPropertiesForKeys: nil)
        check(files.filter { $0.pathExtension == "jsonl" }.count > 1, "Concurrent writers rotate bounded segments under one stable lock")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let original = event(clock)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var bytes = try encoder.encode(original); bytes.append(Data("\nmalformed\n{\"partial\":".utf8))
        try bytes.write(to: root.appendingPathComponent("breakloop.jsonl"))
        let store = PersistentLogStore(directory: root, now: { clock })
        check(FileManager.default.fileExists(atPath: root.appendingPathComponent("breakloop.jsonl").path), "Initialization never erases legacy history")
        store.append(event(clock.addingTimeInterval(1))); check(store.flush(), "Legacy migration and new append complete")
        check(store.history().events.contains { $0.id == original.id }, "Malformed/truncated legacy lines do not lose other events")
        let file = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Diagnostics-v1"), includingPropertiesForKeys: nil).first { $0.pathExtension == "jsonl" }!
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); try handle.write(contentsOf: Data("{\"truncated\":".utf8)); try handle.close()
        store.append(event(clock.addingTimeInterval(2))); _ = store.flush()
        check(store.history().events.count == 3, "Append after interrupted JSONL tail separates damaged line and retains new event")
        let reopened = PersistentLogStore(directory: root, now: { clock })
        check(reopened.history().events.count == 3, "Migration marker prevents duplicate import on update")
        let runtime = root.appendingPathComponent("monitoring-runtime-v1.json")
        let selection = root.appendingPathComponent("selection-fixture")
        try Data("runtime".utf8).write(to: runtime); try Data("selection".utf8).write(to: selection)
        try store.deleteHistory()
        check(store.history().events.isEmpty, "Intentional diagnostic deletion does not reimport old logs")
        check(try Data(contentsOf: runtime) == Data("runtime".utf8) && Data(contentsOf: selection) == Data("selection".utf8), "Diagnostic deletion never clears runtime or selection")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let missing = PersistentLogStore(directory: nil)
        missing.append(event(clock)); _ = missing.flush()
        check(missing.history().error != nil, "Unavailable App Group storage is explicit, without Caches fallback")
        let full = PersistentLogStore(directory: root, beforeWrite: { throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)) })
        full.append(event(clock, level: .error)); _ = full.flush()
        check(full.history().error != nil, "Disk-full error does not crash or pretend durable logging succeeded")
        let fd = open(root.appendingPathComponent("diagnostics.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        flock(fd, LOCK_EX)
        let blocked = PersistentLogStore(directory: root)
        let began = ProcessInfo.processInfo.systemUptime
        blocked.append(event(clock)); check(blocked.flush(timeout: 1), "Log lock contention never blocks callback thread indefinitely")
        check(ProcessInfo.processInfo.systemUptime - began < 1, "Contended archive worker has a bounded lock wait")
        flock(fd, LOCK_UN); close(fd)
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentLogStore(directory: root)
        let logger = AppLogger(persistentStore: store)
        var state = MonitoringRuntime(); state.snapshot = CycleSnapshot(configuration: .default)
        let before = DiagnosticRuntimeSnapshot(state, at: clock)
        state.cooldown = RestrictionDeadline(endsAt: clock.addingTimeInterval(900))
        state.deepFocus = DeepFocusSession(startedAt: clock, durationMinutes: 60)
        state.checkpoint = UsageCheckpointState(usageMinute: 10, timestamp: clock)
        let after = DiagnosticRuntimeSnapshot(state, at: clock)
        logger.withOperation("threshold_callback") {
            logger.record("cooldown_started", category: .cooldown, outcome: "succeeded", before: before, after: after)
            logger.record("shield_apply_attempted", category: .shield, outcome: "attempted", metadata: ["shieldAPIAttempted": "true"])
        }
        _ = store.flush()
        let events = store.history().events
        check(Set(events.compactMap(\.operationID)).count == 1, "Operation scope correlates before/after publication and shield attempt")
        let transition = events.first { $0.event == "cooldown_started" }!
        check(transition.before?.cooldownID == nil && transition.after?.cooldownID == state.cooldown!.id, "Sanitized before/after state captures exact generation transition")
        check(transition.after?.deepFocusID == state.deepFocus!.id && transition.after?.checkpointMinute == 10 && transition.after?.intendsShield == true,
              "Snapshot preserves overlapping ownership and checkpoint progress without full runtime JSON")
        check(events.first { $0.event == "shield_apply_attempted" }?.outcome == "attempted", "Attempted ManagedSettings writes never assert effective enforcement")
        check(events.allSatisfy { $0.processInstanceID != nil && $0.operationID != nil && $0.outcome != nil }, "New events carry process and operation identities and outcomes")
        let filter = DiagnosticFilter(category: .cooldown, level: .info, operationID: transition.operationID)
        check(store.history(filter: filter).events.count == 1, "Category/severity/operation filters select the historical operation")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        var config = DiagnosticArchiveConfiguration(); config.queueCapacity = 4
        let entered = DispatchSemaphore(value: 0); let release = DispatchSemaphore(value: 0)
        var blockedOnce = false
        let store = PersistentLogStore(directory: root, configuration: config, beforeWrite: {
            if !blockedOnce { blockedOnce = true; entered.signal(); _ = release.wait(timeout: .now() + 2) }
        })
        store.append(event(Date(), index: 1))
        check(entered.wait(timeout: .now() + 2) == .success, "Slow storage fixture enters background I/O")
        let began = ProcessInfo.processInfo.systemUptime
        for index in 0..<100 { store.append(event(Date(), index: index)) }
        store.append(event(Date(), index: 999, level: .error))
        check(ProcessInfo.processInfo.systemUptime - began < 1, "Bounded queue leaves logging callers responsive during slow storage")
        release.signal(); _ = store.flush(timeout: 5)
        let history = store.history(limit: 1000)
        check(history.droppedEvents > 0, "Queue pressure is reported instead of unbounded memory growth")
        check(history.events.contains { $0.level == .error && $0.metadata["usageMinute"] == "999" }, "Important failure replaces low-value queued observations")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentLogStore(directory: root)
        let logger = AppLogger(persistentStore: store)
        let fd = open(root.appendingPathComponent("diagnostics.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        flock(fd, LOCK_EX)
        let runtime = RuntimeFileStore(directory: root, didCommit: { before, after, date in
            logger.record("runtime_published", category: .storage, outcome: "succeeded",
                before: before.map { DiagnosticRuntimeSnapshot($0, at: date) }, after: DiagnosticRuntimeSnapshot(after, at: date))
        })
        var first = MonitoringRuntime(); first.snapshot = CycleSnapshot(configuration: .default)
        let began = ProcessInfo.processInfo.systemUptime
        try runtime.withRuntimeLock { try runtime.writeRuntime(first) }
        check(ProcessInfo.processInfo.systemUptime - began < 1, "Runtime publication never waits on the diagnostic file lock")
        check(try runtime.readRuntime() == first, "Log lock failure never changes committed runtime semantics")
        _ = store.flush()
        flock(fd, LOCK_UN); close(fd)
        var second = first; second.cooldown = RestrictionDeadline(endsAt: Date().addingTimeInterval(900))
        try runtime.withRuntimeLock { try runtime.writeRuntime(second) }
        _ = store.flush()
        let publication = store.history().events.last { $0.event == "runtime_published" }!
        check(publication.before?.snapshotID == first.snapshot!.id && publication.before?.cooldownID == nil,
              "Actual production runtime writer captures authoritative before state")
        check(publication.after?.cooldownID == second.cooldown!.id, "Actual production runtime writer captures committed after state without reentrant reads")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let old = event(clock.addingTimeInterval(-8 * 86400))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let defaultsData = try encoder.encode([old])
        let store = PersistentLogStore(directory: root, now: { clock }, legacyDefaults: { defaultsData })
        check(store.history().events.contains { $0.id == old.id }, "Legacy defaults array migrates without deleting its source")
        let reopened = PersistentLogStore(directory: root, now: { clock }, legacyDefaults: { defaultsData })
        check(reopened.history().events.count == 1, "Legacy defaults migration is idempotent across processes/updates")
        let operation = UUID()
        store.append(event(clock, index: 3, operation: operation)); store.append(event(clock.addingTimeInterval(-60), index: 2, operation: operation))
        _ = store.flush()
        let export = root.appendingPathComponent("ordered.jsonl")
        try store.export(filter: DiagnosticFilter(operationID: operation), destination: export)
        let lines = try String(contentsOf: export, encoding: .utf8).split(separator: "\n").dropFirst()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let entries = try lines.map { try decoder.decode(LogEntry.self, from: Data($0.utf8)) }
        check(entries.map(\.timestamp) == entries.map(\.timestamp).sorted() && entries.count == 2, "Out-of-order app/extension events export chronologically with operation correlation")
        let poisoned = LogEntry(id: UUID(), timestamp: clock, level: .error, category: .storage,
            event: "secret_token", message: "SECRET-CONTENT", metadata: ["applicationTokens": "SECRET-TOKEN", "activity": "private.application", "error": "user@example.com"])
        store.append(poisoned); _ = store.flush()
        let raw = String(decoding: try archiveBytes(root), as: UTF8.self)
        check(!raw.contains("SECRET") && !raw.contains("user@example.com") && !raw.contains("private.application") && !raw.contains("secret_token"),
              "Privacy boundary rejects sensitive values even under allowed count keys and unknown action names")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentLogStore(directory: root)
        for suffix in ["", ".DeviceActivityMonitorExtension", ".ShieldActionExtension", ".ShieldConfigurationExtension"] {
            let bundleURL = root.appendingPathComponent(UUID().uuidString + ".bundle")
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            let info: [String: String] = ["CFBundleIdentifier": "com.aliahmeterdogdu.BreakLoop" + suffix,
                "CFBundleVersion": "42", "CFBundleShortVersionString": "1.0.0", "BreakLoopSourceRevision": String(repeating: "a", count: 40)]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundleURL.appendingPathComponent("Info.plist"))
            let logger = AppLogger(persistentStore: store, bundle: Bundle(url: bundleURL)!)
            logger.record("app_launched", category: .lifecycle)
        }
        _ = store.flush()
        let entries = store.history().events
        check(Set(entries.compactMap(\.process)).count == 4, "Main app and all three extensions use compatible process-labelled events")
        check(entries.allSatisfy { $0.appVersion == "1.0.0" && $0.appBuild == "42" && $0.sourceRevision?.count == 40 },
              "Version/build and supplied source revision survive persistence/export schema")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentLogStore(directory: root)
        let original = event(Date()); store.append(original); _ = store.flush()
        try Data("broken manifest".utf8).write(to: root.appendingPathComponent("Diagnostics-v1/manifest.json"))
        let recovered = store.history()
        check(recovered.events.contains { $0.id == original.id }, "Damaged retention metadata never erases valid archived events")
        check(recovered.error != nil && recovered.earlyEvictionAt == nil, "Integrity warning is distinct from actual storage-pressure eviction")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentLogStore(directory: root)
        for index in 0..<40 { store.append(event(Date(), index: index)) }
        _ = store.flush()
        let writer = Process(); writer.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        writer.arguments = ["--diagnostic-writer", root.path, "7"]
        try writer.run()
        let output = root.appendingPathComponent("concurrent-export.jsonl")
        try store.export(filter: DiagnosticFilter(), destination: output)
        writer.waitUntilExit()
        check(writer.terminationStatus == 0, "Writer remains successful during a snapshot export")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let entries = try String(contentsOf: output, encoding: .utf8).split(separator: "\n").dropFirst().map {
            try decoder.decode(LogEntry.self, from: Data($0.utf8))
        }
        check(entries.count >= 40 && entries.count <= 100 && Set(entries.map(\.id)).count == entries.count,
              "Concurrent export contains a coherent unique prefix, never torn JSONL writes")
        check(store.history(limit: 1000).events.count == 100, "Concurrent export never loses or blocks subsequent archived events")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentLogStore(directory: root); let logger = AppLogger(persistentStore: store)
        logger.withOperation("app_foreground") {
            logger.withOperation("reconcile") { logger.failure("reconcile_failed", error: LifecycleError.invalidSchedule, category: .monitoring) }
        }
        _ = store.flush()
        let entries = store.history().events
        let parent = entries.first { $0.event == "app_foreground_attempted" }!.operationID!
        check(entries.filter { $0.event.hasPrefix("reconcile") }.allSatisfy { $0.parentOperationID == parent }, "Nested lifecycle operations retain parent correlation")
        check(entries.first { $0.event == "reconcile_failed" && $0.level == .error }?.metadata["failureCode"] == "invalidSchedule",
              "Typed schedule failure survives sanitization without raw error content")
        check(store.history(filter: DiagnosticFilter(operationID: parent)).events.count == entries.count,
              "Parent-operation filter includes its nested lifecycle events")
    }
    do {
        let root = try temporaryArchive(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentLogStore(directory: root); let logger = AppLogger(persistentStore: store)
        for _ in 0..<2 {
            logger.info("selection_validated", message: "ignored", category: .selection,
                metadata: ["applicationTokens": "4", "webDomainTokens": "1", "result": "rejected", "stage": "start_focus"])
        }
        for _ in 0..<2 {
            logger.info("selection_validated", message: "ignored", category: .selection,
                metadata: ["applicationTokens": "4", "webDomainTokens": "0", "result": "accepted", "stage": "dashboard_read"])
        }
        _ = store.flush()
        let events = store.history().events
        check(events.filter { $0.outcome == "rejected" }.count == 2 && events.count == 3,
              "Important repeated rejections retain counts while unchanged accepted observations are coalesced")
    }

}
