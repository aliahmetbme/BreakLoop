import Foundation

@main struct FirstRunJourneyTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let store = AppGroupStorage()
        let activity = DeviceActivityService()
        let settings = ManagedSettingsService()
        let dashboard = DashboardViewModel(storage: store, deviceActivityService: activity, managedSettingsService: settings)
        check(dashboard.experiencePresentation == .needsSelection, "first launch needs selection")
        check(!dashboard.hasSelection && dashboard.selectionIssue == nil, "empty is guidance, not a storage error")
        store.configuration = CycleConfiguration(usageLimitMinutes: 30, restDurationMinutes: 20)
        let editor = FocusSetupViewModel(storage: store, managedSettingsService: settings, deviceActivityService: activity)
        check(!editor.saveSelection() && store.selected == nil, "empty save rejected")
        editor.selection = FamilyActivitySelection(applicationTokens: [1, 2, 3, 4])
        editor.usageLimitMinutes = 60; editor.restDurationMinutes = 45
        check(editor.saveSelection(), "supported selection saved without writing editor durations")
        check(activity.starts == 0 && settings.writes == 0 && store.runtime.snapshot == nil, "saving never starts either experience or writes shields")
        dashboard.refresh() // The existing editor sheet's onDismiss callback does exactly this.
        check(dashboard.experiencePresentation == .ready && dashboard.hasSelection, "same Dashboard instance becomes ready after dismissal refresh")
        check(dashboard.configuration.usageLimitMinutes == 30 && dashboard.configuration.restDurationMinutes == 20, "Dashboard reads committed durations")
        dashboard.startBreakLoop()
        check(dashboard.state.mode == .monitoring && dashboard.experiencePresentation == .runtime(.monitoring), "explicit Usage Cycle start reaches active runtime")
        check(activity.starts == 1 && store.runtime.snapshot != nil, "existing lifecycle schedules only on explicit start")
        let cycleID = store.runtime.snapshot?.id
        dashboard.presentDeepFocusSheet()
        check(dashboard.startDeepFocus(durationMinutes: 60), "Deep Focus can still start over a running Usage Cycle")
        check(store.runtime.snapshot?.id == cycleID && dashboard.isDeepFocusActive, "overlap preserves the existing cycle generation")
        dashboard.stopDeepFocus()
        check(dashboard.state.mode == .monitoring && store.runtime.snapshot?.id == cycleID, "ending focus returns to the same cycle")
        check(store.runtime.deepFocus == nil, "only the focus owner ends")
        dashboard.stopBreakLoop()
        check(dashboard.experiencePresentation == .ready && store.runtime.snapshot == nil, "stop returns to the equal choices")
        dashboard.presentDeepFocusSheet()
        check(dashboard.isDeepFocusSheetPresented, "Deep Focus entry opens existing duration sheet")
        check(dashboard.startDeepFocus(durationMinutes: 60), "explicit Deep Focus start succeeds")
        let focus = store.runtime.deepFocus
        check(dashboard.experiencePresentation == .runtime(.deepFocus) && focus != nil, "Deep Focus outranks inactive cards")
        let relaunched = DashboardViewModel(storage: store, deviceActivityService: activity, managedSettingsService: settings)
        check(relaunched.configuration == dashboard.configuration && relaunched.selection == editor.selection, "recreated ViewModel reloads existing saved configuration and selection")
        check(store.runtime.deepFocus == focus && relaunched.isDeepFocusActive, "relaunch/read does not replace active session")
        store.selected = nil
        relaunched.refresh()
        check(relaunched.experiencePresentation == .runtime(.deepFocus), "removed selection does not cover active Deep Focus with setup")
        check(store.runtime.deepFocus == focus, "presentation refresh preserves shield owner identity")
        relaunched.stopDeepFocus()
        check(relaunched.experiencePresentation == .needsSelection, "empty guidance returns only after the active session ends")
        store.selected = FamilyActivitySelection(applicationTokens: [1], webDomainTokens: [2])
        relaunched.refresh()
        check(relaunched.experiencePresentation == .repairSelection && !relaunched.hasSelection, "websites are repair state, not empty or ready")
        let failedEditor = FocusSetupViewModel(storage: store, managedSettingsService: settings, deviceActivityService: activity)
        check(!failedEditor.saveSelection(), "website selection cannot save")
        store.failRead = true
        relaunched.refresh()
        check(relaunched.experiencePresentation == .selectionUnavailable && relaunched.displayedError != nil, "read failure outranks cached selection")
        store.failRead = false
        store.selected = FamilyActivitySelection(categoryTokens: [1])
        relaunched.refresh()
        check(relaunched.experiencePresentation == .ready && relaunched.displayedError == nil, "successful re-read clears stale read error without an app restart")
        let retryEditor = FocusSetupViewModel(storage: store, managedSettingsService: settings, deviceActivityService: activity)
        retryEditor.selection = FamilyActivitySelection(applicationTokens: [1, 2])
        store.failSelectionWrite = true
        let previous = store.selected
        check(!retryEditor.saveSelection() && retryEditor.errorMessage != nil, "write failure keeps editor in failed save state")
        check(store.selected == previous, "failed selection persistence does not fabricate a saved selection")
        store.failSelectionWrite = false
        check(retryEditor.saveSelection(), "failed save can be retried explicitly")
        relaunched.refresh()
        check(relaunched.experiencePresentation == .ready && relaunched.selectedAppsCount == 2, "retry re-reads actual saved apps")
        let startedBeforeRefresh = activity.starts
        store.runtime.cooldown = RestrictionDeadline(endsAt: Date().addingTimeInterval(900))
        let deadline = store.runtime.cooldown
        store.selected = nil
        relaunched.refresh()
        check(relaunched.experiencePresentation == .runtime(.cooldown) && store.runtime.cooldown == deadline, "cooldown is not interrupted by empty selection or refresh")
        check(activity.starts == startedBeforeRefresh, "read-only refresh never schedules")
        store.runtime.cooldown = nil
        store.runtime.pendingTransition = PendingMonitoringTransition(addedActivities: [])
        relaunched.refresh()
        check(relaunched.experiencePresentation == .runtime(.loading), "in-flight transition is not first-use setup")
        store.runtime.pendingTransition = nil
        store.runtime.attention = MonitoringAttention(code: .selectionUnsupported, occurredAt: Date(), activity: nil, message: "fixture")
        relaunched.refresh()
        check(relaunched.experiencePresentation == .runtime(.failure), "recovery attention remains distinct from first-use")
        print("First-run journey: \(checks) checks passed (real ViewModels/factory/lifecycle; mock Apple/storage boundary)")
    }
}
