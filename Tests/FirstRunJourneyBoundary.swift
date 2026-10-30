import Foundation

// Host-only substitutes for FamilyControls/storage/Apple APIs. Integers are fixture values,
// not opaque Apple tokens. Production ViewModels, save controller, lifecycle factory and
// lifecycle execute against this injected boundary; no device store is touched.
struct FamilyActivitySelection: Equatable {
    var applicationTokens: Set<Int> = []
    var categoryTokens: Set<Int> = []
    var webDomainTokens: Set<Int> = []
    var breakLoopTokenCounts: SelectionTokenCounts {
        SelectionTokenCounts(applicationTokens: applicationTokens.count, categoryTokens: categoryTokens.count, webDomainTokens: webDomainTokens.count)
    }
    func logBreakLoopCounts(stage: String) {}
}
final class AppGroupStorage: MonitoringRuntimeStore {
    var selected: FamilyActivitySelection?
    var configuration = CycleConfiguration.default
    var runtime = MonitoringRuntime()
    var failRead = false
    var failSelectionWrite = false
    var failConfigurationWrite = false
    private var locked = false
    func loadActivitySelection() throws -> FamilyActivitySelection? {
        if failRead { throw SelectionFailure.corrupted }
        return selected
    }
    func saveActivitySelection(_ value: FamilyActivitySelection) throws {
        try value.breakLoopTokenCounts.saveIfSupported {
            if failSelectionWrite { throw ConfigurationPersistenceError.writeFailed(reason: "fixture") }
            selected = value
        }
    }
    func loadCycleConfiguration() -> CycleConfiguration { configuration }
    func saveCycleConfiguration(_ value: CycleConfiguration) throws {
        if failConfigurationWrite { throw ConfigurationPersistenceError.writeFailed(reason: "fixture") }
        configuration = value
    }
    func withRuntimeLock<T>(_ body: () throws -> T) throws -> T {
        precondition(!locked); locked = true; defer { locked = false }; return try body()
    }
    func withoutRuntimeLock<T>(_ body: () throws -> T) throws -> T {
        precondition(locked); locked = false; defer { locked = true }; return try body()
    }
    func readRuntime() throws -> MonitoringRuntime { runtime }
    func writeRuntime(_ value: MonitoringRuntime) throws { precondition(locked); runtime = value }
}
protocol DeviceActivityServiceProtocol {
    func startMonitoring(selection: FamilyActivitySelection, snapshot: CycleSnapshot) throws
    func startDeadline(name: String, end: Date) throws
    func stopActivities(_ names: [String])
    var activityNames: [String] { get }
    func stopMonitoring()
}
final class DeviceActivityService: DeviceActivityServiceProtocol {
    var activityNames: [String] = []
    var starts = 0
    var failDeadline = false
    var onDeadlineStart: (() -> Void)?
    func startMonitoring(selection: FamilyActivitySelection, snapshot: CycleSnapshot) throws {
        starts += 1; activityNames.append(MonitoringRuntime.focusName(snapshot.id))
    }
    func startDeadline(name: String, end: Date) throws {
        starts += 1
        onDeadlineStart?()
        if failDeadline { throw LifecycleError.invalidSchedule }
        activityNames.append(name)
    }
    func stopActivities(_ names: [String]) { activityNames.removeAll { names.contains($0) } }
    func stopMonitoring() { activityNames = [] }
}
protocol ManagedSettingsServiceProtocol {
    func block(_ selection: FamilyActivitySelection)
    func unblock()
}
final class ManagedSettingsService: ManagedSettingsServiceProtocol {
    var writes = 0
    var clears = 0
    func block(_ selection: FamilyActivitySelection) { writes += 1 }
    func unblock() { writes += 1; clears += 1 }
}
