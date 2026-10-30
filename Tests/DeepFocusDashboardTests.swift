import Foundation

@main struct DeepFocusDashboardTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let store = AppGroupStorage(); store.selected = FamilyActivitySelection(applicationTokens: [1, 2, 3, 4])
        let activity = DeviceActivityService(); let settings = ManagedSettingsService()
        let dashboard = DashboardViewModel(storage: store, deviceActivityService: activity, managedSettingsService: settings)
        check(dashboard.canOfferDeepFocus, "inactive valid selection offers focus")
        dashboard.startBreakLoop()
        store.runtime.checkpoint = UsageCheckpointState(usageMinute: 3, timestamp: Date())
        dashboard.refresh()
        let snapshot = store.runtime.snapshot
        let checkpoint = store.runtime.checkpoint
        let selection = store.selected
        let config = store.configuration
        check(dashboard.canOfferDeepFocus && dashboard.state.mode == .monitoring, "normal monitoring offers focus without stopping it")
        dashboard.presentDeepFocusSheet()
        check(dashboard.isDeepFocusSheetPresented, "active cycle opens duration sheet")
        activity.failDeadline = true
        let clears = settings.clears
        check(!dashboard.startDeepFocus(durationMinutes: 60), "startup failure is not reported as success")
        check(dashboard.isDeepFocusSheetPresented && dashboard.deepFocusErrorMessage != nil, "localized error stays in the open sheet")
        check(dashboard.state.mode == .monitoring && store.runtime.snapshot == snapshot && store.runtime.checkpoint == checkpoint, "failed focus start leaves the normal runtime unchanged")
        check(store.selected == selection && store.configuration == config && settings.clears == clears, "failed start does not change selection, configuration or clear shields")
        let error = dashboard.deepFocusErrorMessage
        dashboard.presentDeepFocusSheet()
        check(dashboard.deepFocusErrorMessage == error, "repeated present cannot discard a visible startup error")
        activity.failDeadline = false
        var duplicate = true
        activity.onDeadlineStart = {
            activity.onDeadlineStart = nil
            duplicate = dashboard.startDeepFocus(durationMinutes: 60)
            dashboard.presentDeepFocusSheet()
        }
        let starts = activity.starts
        check(dashboard.startDeepFocus(durationMinutes: 60), "explicit retry succeeds")
        check(!duplicate && activity.starts == starts + 1, "reentrant repeated launch is rejected without a duplicate schedule")
        check(store.runtime.snapshot == snapshot && store.runtime.checkpoint == checkpoint, "successful focus preserves exact cycle and checkpoint")
        check(!dashboard.isDeepFocusSheetPresented && dashboard.deepFocusErrorMessage == nil, "only successful start closes and clears sheet")
        check(!dashboard.canOfferDeepFocus && dashboard.focusCompanionState == .usageCycle, "focus foregrounds while reporting the underlying cycle")
        let focus = store.runtime.deepFocus
        check(!dashboard.startDeepFocus(durationMinutes: 30) && store.runtime.deepFocus == focus, "active focus cannot be relaunched through the ViewModel")
        dashboard.presentDeepFocusSheet()
        check(!dashboard.isDeepFocusSheetPresented, "active focus cannot open duplicate setup")
        let relaunched = DashboardViewModel(storage: store, deviceActivityService: activity, managedSettingsService: settings)
        check(relaunched.isDeepFocusActive && relaunched.focusCompanionState == .usageCycle, "relaunch read foregrounds focus and reports underlying cycle")
        relaunched.refresh()
        check(store.runtime.deepFocus == focus && store.runtime.snapshot == snapshot && store.runtime.checkpoint == checkpoint, "read-only refresh does not reset either activity")
        relaunched.stopDeepFocus()
        check(relaunched.state.mode == .monitoring && relaunched.canOfferDeepFocus && store.runtime.snapshot == snapshot && store.runtime.checkpoint == checkpoint, "ending focus restores the same normal cycle and action")
        relaunched.stopBreakLoop()
        check(relaunched.state.mode == .inactive && store.runtime.snapshot == nil && store.runtime.checkpoint == nil,
              "quiet Stop Usage Cycle action still ends the normal cycle")
        check(activity.activityNames.isEmpty, "Stop removes the existing normal monitoring schedule")
        check(store.selected == selection && store.configuration == config, "Stop preserves saved selection and configuration")
        relaunched.startBreakLoop()
        for invalid in [FamilyActivitySelection(), FamilyActivitySelection(applicationTokens: [1], webDomainTokens: [2])] {
            store.selected = invalid; relaunched.refresh()
            check(!relaunched.canOfferDeepFocus, "empty/unsupported selection hides focus entry during monitoring")
            relaunched.presentDeepFocusSheet()
            check(!relaunched.isDeepFocusSheetPresented, "invalid selection cannot open focus setup")
        }
        store.selected = selection
        store.failRead = true; relaunched.refresh()
        check(!relaunched.canOfferDeepFocus, "read failure does not offer focus from cached tokens")
        store.failRead = false
        store.runtime.cooldown = RestrictionDeadline(endsAt: Date().addingTimeInterval(900))
        relaunched.refresh()
        check(!relaunched.canOfferDeepFocus && relaunched.state.mode == .cooldown, "cooldown availability is not broadened")
        store.runtime.cooldown = nil
        store.runtime.pendingTransition = PendingMonitoringTransition(addedActivities: [])
        relaunched.refresh()
        check(!relaunched.canOfferDeepFocus && relaunched.state.mode == .loading, "pending transition blocks focus")
        store.runtime.pendingTransition = nil
        store.runtime.attention = MonitoringAttention(code: .monitorUnavailable, occurredAt: Date(), activity: nil, message: "fixture")
        relaunched.refresh()
        check(!relaunched.canOfferDeepFocus && relaunched.state.mode == .failure, "recovery state blocks focus")
        print("Deep Focus Dashboard: \(checks) checks passed (real ViewModels/factory/lifecycle; mock Apple/storage boundary)")
    }
}
