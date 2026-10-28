import Foundation
import Darwin

struct DiagnosticArchiveConfiguration {
    var retentionDays = 14
    var maximumBytes = 50 * 1024 * 1024
    var segmentBytes = 1024 * 1024
    var queueCapacity = 512
    var lockTimeout: TimeInterval = 0.05
}
struct DiagnosticFilter {
    var start = Date.distantPast
    var end = Date.distantFuture
    var category: LogCategory?
    var level: LogLevel?
    var operationID: UUID?
    func includes(_ entry: LogEntry) -> Bool {
        entry.timestamp >= start && entry.timestamp <= end && (category == nil || entry.category == category)
            && (level == nil || entry.level == level) && (operationID == nil || entry.operationID == operationID || entry.parentOperationID == operationID)
    }
}
struct DiagnosticHistory {
    var events: [LogEntry]
    var oldest: Date?
    var newest: Date?
    var bytes: Int
    var earlyEvictionAt: Date?
    var droppedEvents: Int
    var error: String?
    var maximumBytes = 50 * 1024 * 1024
    var retentionDays = 14
}
private struct ArchiveManifest: Codable {
    var earlyEvictionAt: Date?
    var droppedEvents = 0
    var legacyDefaultsImported = false
    var integrityWarning: Bool?
}
enum DiagnosticArchiveError: LocalizedError {
    case unavailable, busy, oversized
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Diagnostic App Group storage is unavailable. No Caches fallback was used."
        case .busy: return "Diagnostics are busy. Retry shortly."
        case .oversized: return "Diagnostic event exceeds the configured archive budget."
        }
    }
}

// Queueing never takes the runtime lock. Only this archive's stable, dedicated lock protects files.
final class PersistentLogStore: @unchecked Sendable {
    static let shared = PersistentLogStore(
        directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.aliahmeterdogdu.BreakLoop"),
        legacyDefaults: { UserDefaults(suiteName: "group.com.aliahmeterdogdu.BreakLoop")?.data(forKey: "breakloop.logs") })
    private let root: URL?
    private let config: DiagnosticArchiveConfiguration
    private let now: () -> Date
    private let legacyDefaults: () -> Data?
    private let worker = DispatchQueue(label: "breakloop.diagnostics.archive", qos: .utility)
    private let queueLock = NSLock()
    private var pending: [LogEntry] = []
    private var draining = false
    private var dropped = 0
    private var lastError: String?
    // Fault injection uses the exact production I/O path, without allocating a full disk.
    private let beforeWrite: () throws -> Void

    init(directory: URL?, configuration: DiagnosticArchiveConfiguration = DiagnosticArchiveConfiguration(),
         now: @escaping () -> Date = Date.init, legacyDefaults: @escaping () -> Data? = { nil },
         beforeWrite: @escaping () throws -> Void = {}) {
        root = directory; config = configuration; self.now = now
        self.legacyDefaults = legacyDefaults; self.beforeWrite = beforeWrite
        // No filesystem work, deletion or migration during initialization.
    }

    func append(_ entry: LogEntry) {
        let safe = entry.sanitized()
        queueLock.lock()
        if pending.count >= max(1, config.queueCapacity) {
            if safe.level == .error || safe.level == .warning,
               let low = pending.firstIndex(where: { $0.level == .debug || $0.level == .info }) {
                pending.remove(at: low); dropped += 1
            } else { dropped += 1; queueLock.unlock(); return }
        }
        pending.append(safe)
        let start = !draining; draining = true
        queueLock.unlock()
        if start { worker.async { self.drain() } }
    }

    private func drain() {
        while true {
            queueLock.lock()
            guard !pending.isEmpty else { draining = false; queueLock.unlock(); return }
            let batch = Array(pending.prefix(64)); pending.removeFirst(batch.count)
            let lost = dropped; dropped = 0
            queueLock.unlock()
            do {
                try locked(timeout: config.lockTimeout) { folder in
                    var manifest = try readManifest(folder)
                    try migrate(folder, manifest: &manifest)
                    manifest.droppedEvents += lost
                    for entry in batch { try write(entry, folder: folder, manifest: &manifest) }
                    try saveManifest(manifest, folder)
                }
                queueLock.lock(); lastError = nil; queueLock.unlock()
            } catch {
                // Bounded loss instead of blocking/retrying Screen Time callbacks indefinitely.
                queueLock.lock(); dropped += batch.count + lost
                lastError = error is DiagnosticArchiveError ? error.localizedDescription : "Diagnostic archive write failed (storage error)."
                queueLock.unlock()
            }
        }
    }

    // Call from a background task/diagnostics UI or tests, never synchronously from a Screen Time callback.
    @discardableResult func flush(timeout: TimeInterval = 2) -> Bool {
        let signal = DispatchSemaphore(value: 0)
        worker.async { signal.signal() }
        return signal.wait(timeout: .now() + timeout) == .success
    }
    func flushAsync() { worker.async {} }

    private func locked<T>(timeout: TimeInterval, _ body: (URL) throws -> T) throws -> T {
        guard let root else { throw DiagnosticArchiveError.unavailable }
        let fd = open(root.appendingPathComponent("diagnostics.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw DiagnosticArchiveError.unavailable }
        defer { close(fd) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw DiagnosticArchiveError.busy }
            usleep(1000)
        }
        defer { flock(fd, LOCK_UN) }
        let folder = root.appendingPathComponent("Diagnostics-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try body(folder)
    }
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys; return encoder
    }
    private func decode(_ data: Data) -> LogEntry? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        if let entry = try? decoder.decode(LogEntry.self, from: data) { return entry.sanitized() }
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LogEntry.self, from: data))?.sanitized()
    }
    private func readManifest(_ folder: URL) throws -> ArchiveManifest {
        let url = folder.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return ArchiveManifest() }
        // A damaged manifest must not erase segments. Warn conservatively that history may be incomplete.
        return (try? JSONDecoder().decode(ArchiveManifest.self, from: Data(contentsOf: url)))
            ?? ArchiveManifest(integrityWarning: true)
    }
    private func saveManifest(_ manifest: ArchiveManifest, _ folder: URL) throws {
        try beforeWrite()
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }
    private func files(_ folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func size(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    private func day(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    private func cutoffDay() -> String {
        day(now().addingTimeInterval(-Double(max(14, config.retentionDays)) * 86400))
    }
    // Stream line-by-line in bounded chunks. An oversized/corrupt line is skipped, not the entire file.
    @discardableResult private func scan(_ url: URL, _ consume: (LogEntry) throws -> Void) throws -> Int {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        return try scan(handle, bytes: nil, consume)
    }
    @discardableResult private func scan(_ handle: FileHandle, bytes: Int?, _ consume: (LogEntry) throws -> Void) throws -> Int {
        var buffer = Data(); var oversized = false; var malformed = 0
        var remaining = bytes ?? Int.max
        while remaining > 0, let chunk = try handle.read(upToCount: min(remaining, 64 * 1024)), !chunk.isEmpty {
            remaining -= chunk.count
            for byte in chunk {
                if byte == 10 {
                    if !oversized, let entry = decode(buffer) { try consume(entry) }
                    else if !buffer.isEmpty || oversized { malformed += 1 }
                    buffer.removeAll(keepingCapacity: true); oversized = false
                } else if buffer.count < 64 * 1024 { buffer.append(byte) }
                else { oversized = true }
            }
        }
        if !oversized, let entry = decode(buffer) { try consume(entry) }
        else if !buffer.isEmpty || oversized { malformed += 1 }
        return malformed
    }
    private func migrate(_ folder: URL, manifest: inout ArchiveManifest) throws {
        guard !manifest.legacyDefaultsImported, let root else { return }
        var known: Set<UUID> = []
        for file in try files(folder) { try scan(file) { known.insert($0.id) } }
        func importEntry(_ entry: LogEntry) throws {
            guard known.insert(entry.id).inserted else { return }
            try write(entry.sanitized(), folder: folder, manifest: &manifest)
        }
        // Preserve original sources in place; sanitized copies retain event IDs/times. A partial
        // import is retried idempotently. No legacy key/file is deleted during initialization/migration.
        for name in ["breakloop.old.jsonl", "breakloop.jsonl"] {
            let source = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                if try scan(source, importEntry) > 0 { manifest.integrityWarning = true }
            }
        }
        if let data = legacyDefaults() {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            var entries = try? decoder.decode([LogEntry].self, from: data)
            if entries == nil {
                let first = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
                let timestamp = first?.first?["timestamp"] as? Double
                decoder.dateDecodingStrategy = (timestamp ?? 0) > 100_000_000_000 ? .millisecondsSince1970 : .deferredToDate
                entries = try? decoder.decode([LogEntry].self, from: data)
            }
            if let entries { for entry in entries { try importEntry(entry) } }
            else { manifest.integrityWarning = true }
        }
        manifest.legacyDefaultsImported = true
        try saveManifest(manifest, folder)
    }
    private func prune(_ folder: URL) throws {
        for file in try files(folder) where String(file.lastPathComponent.prefix(10)) < cutoffDay() {
            try FileManager.default.removeItem(at: file)
        }
    }
    private func write(_ entry: LogEntry, folder: URL, manifest: inout ArchiveManifest) throws {
        let data = try encoder().encode(entry.sanitized()) + Data([10])
        guard config.maximumBytes >= 8192 else { throw DiagnosticArchiveError.oversized }
        let budget = config.maximumBytes - 4096 // Manifest/metadata reserve.
        guard data.count <= budget && data.count <= 64 * 1024 else { throw DiagnosticArchiveError.oversized }
        try prune(folder)
        var archive = try files(folder)
        var total = archive.reduce(0) { $0 + size($1) }
        while total + data.count > budget, let oldest = archive.first {
            manifest.earlyEvictionAt = now()
            // Persist the warning BEFORE eviction, including across a crash/disk-full failure.
            try saveManifest(manifest, folder)
            try FileManager.default.removeItem(at: oldest)
            archive.removeFirst(); total = archive.reduce(0) { $0 + size($1) }
        }
        let prefix = day(entry.timestamp)
        let candidates = archive.filter { $0.lastPathComponent.hasPrefix(prefix) }
        let last = candidates.last
        let threshold = max(512, min(config.segmentBytes, budget))
        var url: URL
        if let last, size(last) + data.count + 1 <= threshold { url = last }
        else {
            let index = (candidates.compactMap { Int($0.deletingPathExtension().lastPathComponent.split(separator: ".").last ?? "") }.max() ?? -1) + 1
            url = folder.appendingPathComponent(String(format: "%@.%06d.jsonl", prefix, index))
        }
        try beforeWrite()
        let fd = open(url.path, O_CREAT | O_RDWR | O_APPEND, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw DiagnosticArchiveError.unavailable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        if length > 0 {
            try handle.seek(toOffset: length - 1)
            if try handle.read(upToCount: 1) != Data([10]) { try handle.write(contentsOf: Data([10])) }
        }
        try handle.write(contentsOf: data)
        if entry.level == .error || entry.level == .warning { try handle.synchronize() }
    }

    private struct ReadSnapshot {
        let segments: [(FileHandle, Int)]
        let manifest: ArchiveManifest
        let migrationIncomplete: Bool
        var bytes: Int { segments.reduce(0) { $0 + $1.1 } }
        func close() { segments.forEach { try? $0.0.close() } }
    }
    private func readSnapshot() throws -> ReadSnapshot {
        try locked(timeout: 2) { folder in
            var manifest = try readManifest(folder)
            var incomplete = false
            do { try migrate(folder, manifest: &manifest) } catch { incomplete = true }
            try prune(folder)
            var opened: [(FileHandle, Int)] = []
            do {
                for file in try files(folder) {
                    let handle = try FileHandle(forReadingFrom: file)
                    let length = try handle.seekToEnd(); try handle.seek(toOffset: 0)
                    opened.append((handle, Int(length)))
                }
            } catch { opened.forEach { try? $0.0.close() }; throw error }
            // Open descriptors pin each inode; captured lengths exclude all later appends.
            // Retention may unlink a segment, but this immutable read prefix stays available.
            return ReadSnapshot(segments: opened, manifest: manifest, migrationIncomplete: incomplete)
        }
    }
    func history(filter: DiagnosticFilter = DiagnosticFilter(), limit: Int = 300) -> DiagnosticHistory {
        let completed = flush()
        do {
            let snapshot = try readSnapshot(); defer { snapshot.close() }
            var newest: Date?; var oldest: Date?; var entries: [LogEntry] = []; var seen: Set<UUID> = []; var malformed = 0
            for (handle, length) in snapshot.segments {
                malformed += try scan(handle, bytes: length) { entry in
                    oldest = min(oldest ?? .distantFuture, entry.timestamp); newest = max(newest ?? .distantPast, entry.timestamp)
                    if filter.includes(entry), seen.insert(entry.id).inserted {
                        entries.append(entry)
                        if entries.count > max(1, limit) * 2 { entries.sort(by: Self.order); entries.removeFirst(entries.count - max(1, limit)) }
                    }
                }
            }
            entries.sort(by: Self.order)
            queueLock.lock(); let error = lastError; let lost = dropped; queueLock.unlock()
            let status = !completed ? "Pending diagnostic events have not finished flushing." :
                (snapshot.migrationIncomplete ? "Legacy migration is incomplete; existing archived events remain readable." :
                    (error ?? ((malformed > 0 || snapshot.manifest.integrityWarning == true) ? "Malformed/interrupted lines or damaged metadata were recovered; some diagnostic history may be incomplete." : nil)))
            return DiagnosticHistory(events: Array(entries.suffix(max(1, limit))), oldest: oldest, newest: newest,
                bytes: snapshot.bytes, earlyEvictionAt: snapshot.manifest.earlyEvictionAt,
                droppedEvents: snapshot.manifest.droppedEvents + lost, error: status,
                maximumBytes: config.maximumBytes, retentionDays: max(14, config.retentionDays))
        } catch { return DiagnosticHistory(events: [], bytes: 0, droppedEvents: 0, error: error.localizedDescription) }
    }
    private static func order(_ lhs: LogEntry, _ rhs: LogEntry) -> Bool {
        lhs.timestamp == rhs.timestamp ? lhs.id.uuidString < rhs.id.uuidString : lhs.timestamp < rhs.timestamp
    }
    func export(filter: DiagnosticFilter, destination: URL) throws {
        guard flush(timeout: 5) else { throw DiagnosticArchiveError.busy }
        let snapshot = try readSnapshot(); defer { snapshot.close() }
        let temporary = destination.appendingPathExtension("partial")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.truncate(atOffset: 0)
            let manifest = snapshot.manifest
            let summary: [String: Any] = ["type": "breakloop_diagnostic_manifest", "schemaVersion": 1,
                "exportedAt": now().timeIntervalSince1970 * 1000, "timestampEncoding": "millisecondsSince1970",
                "rangeStart": filter.start.timeIntervalSince1970 * 1000, "rangeEnd": filter.end.timeIntervalSince1970 * 1000,
                "category": filter.category?.rawValue ?? "all", "severity": filter.level?.rawValue ?? "all",
                "operationID": filter.operationID?.uuidString ?? "all", "retentionDays": max(14, config.retentionDays),
                "maximumBytes": config.maximumBytes, "droppedEvents": manifest.droppedEvents,
                "migrationIncomplete": snapshot.migrationIncomplete, "integrityWarning": manifest.integrityWarning ?? false,
                "earlyEvictionAt": manifest.earlyEvictionAt.map { $0.timeIntervalSince1970 * 1000 } as Any? ?? NSNull()]
            try handle.write(contentsOf: JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]) + Data([10]))
            var seen: Set<UUID> = []; var entries: [LogEntry] = []
            for (source, length) in snapshot.segments {
                try scan(source, bytes: length) { if filter.includes($0), seen.insert($0.id).inserted { entries.append($0) } }
            }
            let json = encoder()
            for entry in entries.sorted(by: Self.order) { try handle.write(contentsOf: json.encode(entry.sanitized()) + Data([10])) }
            try handle.close()
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch { try? handle.close(); try? FileManager.default.removeItem(at: temporary); throw error }
    }
    // Called only by the separate, confirmed Diagnostics deletion UI. Runtime/preferences are untouched.
    func deleteHistory() throws {
        guard flush(timeout: 5) else { throw DiagnosticArchiveError.busy }
        try locked(timeout: 2) { folder in
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: file) }
            if let root {
                for name in ["breakloop.old.jsonl", "breakloop.jsonl"] {
                    let url = root.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                }
            }
            // Tombstone prevents old defaults history being silently reimported after intentional deletion.
            var manifest = ArchiveManifest(); manifest.legacyDefaultsImported = true
            try saveManifest(manifest, folder)
        }
    }
    func loadRecent(limit: Int = 100) -> [LogEntry] { history(limit: limit).events }
    func loadLogs() -> [LogEntry] { loadRecent(limit: 300) }
}
