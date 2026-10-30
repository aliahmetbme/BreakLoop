import Foundation
@main struct SettingsConfigurationTests {
    @MainActor static func main() {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) { count += 1; precondition(value(), message) }
        let storage = AppGroupStorage()
        let original = CycleConfiguration(usageLimitMinutes: 35, restDurationMinutes: 25)
        storage.configuration = original
        storage.selected = FamilyActivitySelection(applicationTokens: [1,2])
        storage.runtime.snapshot = CycleSnapshot(configuration: original)
        storage.runtime.checkpoint = UsageCheckpointState(usageMinute: 4, timestamp: Date())
        let runtime = storage.runtime; let selection = storage.selected
        let model = SettingsViewModel(storage: storage)
        check(model.committedConfiguration == original, "canonical editor loads saved configuration")
        storage.failConfigurationWrite = true
        model.updateUsageLimit(50)
        check(model.hasUnsavedChanges && model.errorMessage != nil, "failed save keeps visible pending edits")
        check(model.committedConfiguration == original && storage.configuration == original, "failed save retains durable configuration")
        check(storage.runtime == runtime && storage.selected == selection, "failed configuration save cannot mutate runtime/selection")
        model.revertUnsavedChanges()
        check(!model.hasUnsavedChanges && model.usageLimitMinutes == 35 && model.errorMessage == nil, "discard restores committed duration")
        storage.failConfigurationWrite = false
        model.updateUsageLimit(50); model.updateRestDuration(40)
        check(storage.configuration == CycleConfiguration(usageLimitMinutes: 50, restDurationMinutes: 40), "canonical duration editor persists configured next-cycle values")
        check(!model.hasUnsavedChanges && model.errorMessage == nil, "successful save clears pending error")
        check(storage.runtime == runtime && model.activeSnapshot == runtime.snapshot, "settings save leaves active snapshot/checkpoint isolated")
        let dashboard = DashboardViewModel(storage: storage, deviceActivityService: DeviceActivityService(), managedSettingsService: ManagedSettingsService())
        check(dashboard.effectiveLimitMinutes == 35 && dashboard.effectiveRestMinutes == 25, "Dashboard keeps effective original active configuration")
        check(storage.selected == selection, "duration editing does not rewrite selection")
        print("Settings configuration save/failure: \(count) checks passed")
    }
}
