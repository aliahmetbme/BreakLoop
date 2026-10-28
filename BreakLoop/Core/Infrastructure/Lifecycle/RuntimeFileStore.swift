import Foundation
import Darwin

// All processes lock the same inode. The JSON file can then be atomically replaced without
// invalidating the lock. Never lock the JSON file itself, whose inode changes on every commit.
final class RuntimeFileStore: MonitoringRuntimeStore {
    private let directory: URL
    private var changedUnderLock = false
    private let didCommit: (MonitoringRuntime, Date) -> Void
    private let didChange: () -> Void
    private let migrate: () throws -> MonitoringRuntime
    var recordURL: URL { directory.appendingPathComponent("monitoring-runtime-v1.json") }

    init(directory: URL, migrate: @escaping () throws -> MonitoringRuntime = { MonitoringRuntime() },
         didChange: @escaping () -> Void = {},
         didCommit: @escaping (MonitoringRuntime, Date) -> Void = { _, _ in }) {
        self.directory = directory; self.migrate = migrate; self.didChange = didChange; self.didCommit = didCommit
    }

    func withRuntimeLock<T>(_ body: () throws -> T) throws -> T {
        let fd = open(directory.appendingPathComponent("monitoring-runtime.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LifecycleError.storageUnavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw LifecycleError.storageUnavailable }
        changedUnderLock = false
        defer {
            let changed = changedUnderLock
            changedUnderLock = false
            flock(fd, LOCK_UN)
            // A callback may read/reacquire the lock. Never signal while the transaction holds it.
            if changed { didChange() }
        }
        return try body()
    }

    func readRuntime() throws -> MonitoringRuntime {
        if FileManager.default.fileExists(atPath: recordURL.path) {
            return try JSONDecoder().decode(MonitoringRuntime.self, from: Data(contentsOf: recordURL))
        }
        return try migrate()
    }

    func writeRuntime(_ state: MonitoringRuntime) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(state)
        if FileManager.default.fileExists(atPath: recordURL.path), try Data(contentsOf: recordURL) == data { return }
        try data.write(to: recordURL, options: .atomic)
        changedUnderLock = true
        didCommit(state, Date())
    }
}
