import Foundation
import Darwin
import OSLog

// Stable lock inode; the JSON inode is atomically replaced. A lease is thread-local so
// callbacks/other threads can acquire their own descriptor while an Apple call is in flight.
final class RuntimeFileStore: MonitoringRuntimeStore {
    private final class Lease {
        let descriptor: Int32
        var held = false
        var changed = false
        var previousDepth: Any?
        var hold: (UUID, OSSignpostID, TimeInterval)?
        init(_ descriptor: Int32) { self.descriptor = descriptor }
    }
    private let directory: URL
    private let contextKey = "breakloop.runtime.lease." + UUID().uuidString
    private let didCommit: (MonitoringRuntime?, MonitoringRuntime, Date) -> Void
    private let didChange: () -> Void
    private let migrate: () throws -> MonitoringRuntime
    var recordURL: URL { directory.appendingPathComponent("monitoring-runtime-v1.json") }

    init(directory: URL, migrate: @escaping () throws -> MonitoringRuntime = { MonitoringRuntime() },
         didChange: @escaping () -> Void = {},
         didCommit: @escaping (MonitoringRuntime?, MonitoringRuntime, Date) -> Void = { _, _, _ in }) {
        self.directory = directory; self.migrate = migrate; self.didChange = didChange; self.didCommit = didCommit
    }

    private func acquire(_ lease: Lease) throws {
        let wait = AppLogger.shared.timingBegin("runtime_lock_wait")
        guard flock(lease.descriptor, LOCK_EX) == 0 else {
            AppLogger.shared.timingEnd("runtime_lock_wait", span: wait, failed: true)
            throw LifecycleError.storageUnavailable
        }
        AppLogger.shared.timingEnd("runtime_lock_wait", span: wait)
        lease.held = true
        lease.previousDepth = Thread.current.threadDictionary[RuntimeLockContext.key]
        Thread.current.threadDictionary[RuntimeLockContext.key] = (lease.previousDepth as? Int ?? 0) + 1
        lease.hold = AppLogger.shared.timingBegin("runtime_lock_hold")
    }

    private func release(_ lease: Lease) {
        guard lease.held else { return }
        let changed = lease.changed
        lease.changed = false; lease.held = false
        flock(lease.descriptor, LOCK_UN)
        Thread.current.threadDictionary[RuntimeLockContext.key] = lease.previousDepth
        if let hold = lease.hold { AppLogger.shared.timingEnd("runtime_lock_hold", span: hold) }
        lease.hold = nil
        // Never drain logging or signal while the runtime file lock is held.
        if changed { didChange() }
    }

    func withRuntimeLock<T>(_ body: () throws -> T) throws -> T {
        precondition((Thread.current.threadDictionary[contextKey] as? Lease)?.held != true, "Nested runtime lock")
        let fd = open(directory.appendingPathComponent("monitoring-runtime.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LifecycleError.storageUnavailable }
        defer { close(fd) }
        let previous = Thread.current.threadDictionary[contextKey]
        let lease = Lease(fd)
        Thread.current.threadDictionary[contextKey] = lease
        defer { release(lease); Thread.current.threadDictionary[contextKey] = previous }
        try acquire(lease)
        return try body()
    }

    func withoutRuntimeLock<T>(_ body: () throws -> T) throws -> T {
        guard let lease = Thread.current.threadDictionary[contextKey] as? Lease, lease.held else {
            throw LifecycleError.storageUnavailable
        }
        release(lease)
        let result = Result { try body() }
        // Reacquire even when the system API throws. The caller must revalidate its intent
        // or authoritative generation before publishing any previously computed state.
        try acquire(lease)
        return try result.get()
    }

    func readRuntime() throws -> MonitoringRuntime {
        if FileManager.default.fileExists(atPath: recordURL.path) {
            return try JSONDecoder().decode(MonitoringRuntime.self, from: Data(contentsOf: recordURL))
        }
        return try migrate()
    }

    func writeRuntime(_ state: MonitoringRuntime) throws {
        guard let lease = Thread.current.threadDictionary[contextKey] as? Lease, lease.held else {
            throw LifecycleError.storageUnavailable
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(state)
        var before: MonitoringRuntime?
        if FileManager.default.fileExists(atPath: recordURL.path) {
            let previous = try Data(contentsOf: recordURL)
            if previous == data { return }
            before = try? JSONDecoder().decode(MonitoringRuntime.self, from: previous)
        }
        try data.write(to: recordURL, options: .atomic)
        lease.changed = true
        didCommit(before, state, Date())
    }
}
