import Foundation

@main struct SiblingExperienceTests {
    @MainActor static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) { count += 1; precondition(value(), message) }
        let store = AppGroupStorage()
        store.configuration = CycleConfiguration(usageLimitMinutes: 35, restDurationMinutes: 25)
        store.selected = FamilyActivitySelection(applicationTokens: [1,2,3,4])
        let activity = DeviceActivityService(); let shields = ManagedSettingsService()
        let model = DashboardViewModel(storage: store, deviceActivityService: activity, managedSettingsService: shields)
        check(model.state.usageCycleState.mode == .inactive && model.canOfferDeepFocus, "two inactive choices")
        model.startBreakLoop()
        let snapshot = store.runtime.snapshot!
        store.runtime.checkpoint = UsageCheckpointState(usageMinute: 3, timestamp: Date())
        model.refresh()
        check(model.state.usageCycleState.mode == .monitoring, "normal cycle active")
        let editor = FocusSetupViewModel(storage: store, managedSettingsService: shields, deviceActivityService: activity)
        editor.usageLimitMinutes = 90; editor.restDurationMinutes = 60
        editor.selection = FamilyActivitySelection(applicationTokens: [5,6])
        let before = store.runtime; let names = activity.activityNames; let writes = shields.writes
        check(editor.saveSelection(), "selection-only save succeeds")
        check(store.configuration == CycleConfiguration(usageLimitMinutes: 35, restDurationMinutes: 25), "selection save never writes duration configuration")
        check(store.runtime == before && activity.activityNames == names && shields.writes == writes, "selection save cannot restart monitoring, reset checkpoint or write shields")
        store.failSelectionWrite = true
        editor.selection = FamilyActivitySelection(categoryTokens: [3])
        check(!editor.saveSelection() && editor.errorMessage != nil, "selection persistence failure stays visible")
        check(store.selected?.applicationTokens == [5,6] && store.configuration.usageLimitMinutes == 35, "failed selection save preserves prior selection/config")
        store.failSelectionWrite = false
        editor.selection = FamilyActivitySelection(applicationTokens: [5], webDomainTokens: [9])
        check(!editor.saveSelection(), "website selection rejected explicitly")
        model.refresh(); model.presentDeepFocusSheet()
        check(model.startDeepFocus(durationMinutes: 60), "focus can launch over original cycle")
        let focus = store.runtime.deepFocus!
        check(model.state.mode == .deepFocus && model.state.usageCycleState.mode == .monitoring, "both sibling cards reflect actual owners")
        check(store.runtime.snapshot == snapshot && store.runtime.checkpoint == before.checkpoint, "overlap preserves original budget/checkpoint")
        store.configuration = CycleConfiguration(usageLimitMinutes: 50, restDurationMinutes: 40)
        model.refresh()
        check(model.effectiveLimitMinutes == 35 && model.effectiveRestMinutes == 25, "active card uses snapshot, not edited next-cycle values")
        model.stopBreakLoop()
        check(store.runtime.deepFocus == focus && store.runtime.snapshot == nil, "independent cycle stop preserves focus owner")
        check(model.state.usageCycleState.mode == .inactive && model.isDeepFocusActive, "focus alone leaves cycle visibly inactive")
        model.stopDeepFocus()
        check(model.state.mode == .inactive, "last owner ends normally")
        model.startBreakLoop(); model.presentDeepFocusSheet(); check(model.startDeepFocus(durationMinutes: 60), "overlap can restart explicitly")
        store.runtime.cooldown = RestrictionDeadline(endsAt: Date().addingTimeInterval(900)); model.refresh()
        let cooldown = store.runtime.cooldown
        check(model.state.usageCycleState.mode == .cooldown && model.isDeepFocusActive, "cooldown remains visible under focus")
        model.stopDeepFocus()
        check(store.runtime.cooldown == cooldown && model.state.usageCycleState.mode == .cooldown, "ending focus preserves cooldown")
        store.runtime.pendingTransition = PendingMonitoringTransition(addedActivities: []); model.refresh()
        check(model.state.usageCycleState.mode == .loading && !model.canOfferDeepFocus, "pending runtime cannot offer starts")
        let failed = DashboardState(runtime: store.runtime, synchronizationError: "fixture")
        check(failed.usageCycleState.mode == .failure && !failed.canConfigureDeepFocus, "unverified state retains recovery")
        check(DashboardState.loading.usageCycleState.mode == .loading, "initial read keeps loading")
        print("Sibling experience / selection isolation: \(count) checks passed")
    }
}
