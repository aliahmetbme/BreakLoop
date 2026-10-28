import Foundation
import Darwin

// All processes lock the same inode. The JSON file can then be atomically replaced without
// invalidating the lock. Never lock the JSON file itself, whose inode changes on every commit.
final class RuntimeFileStore: MonitoringRuntimeStore {
    private let directory: URL
    private let migrate: () throws -> MonitoringRuntime
    var recordURL: URL { directory.appendingPathComponent("monitoring-runtime-v1.json") }

    init(directory: URL, migrate: @escaping () throws -> MonitoringRuntime = { MonitoringRuntime() }) {
        self.directory = directory; self.migrate = migrate
    }

    func withRuntimeLock<T>(_ body: () throws -> T) throws -> T {
        let fd = open(directory.appendingPathComponent("monitoring-runtime.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LifecycleError.storageUnavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw LifecycleError.storageUnavailable }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    func readRuntime() throws -> MonitoringRuntime {
        if FileManager.default.fileExists(atPath: recordURL.path) {
            return try JSONDecoder().decode(MonitoringRuntime.self, from: Data(contentsOf: recordURL))
        }
        return try migrate()
    }

    func writeRuntime(_ state: MonitoringRuntime) throws {
        try JSONEncoder().encode(state).write(to: recordURL, options: .atomic)
    }
}
