import Foundation

@MainActor
func runCooldownSelectionRegressionTests() throws {
    do {
        let h = Harness()
        h.config = CycleConfiguration(usageLimitMinutes: 10, restDurationMinutes: 15)
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4))
        try h.cooldown()
        let originalConfiguration = h.config
        let oldID = h.store.state.snapshot!.id
        h.time = h.store.state.cooldown!.endsAt
        try h.sut.reconcile()
        check(h.store.state.snapshot != nil && h.store.state.cooldown == nil, "Four-app-only selection restarts focus after expiry")
        check(h.store.state.snapshot!.id != oldID && h.monitored.count == 1, "Expiry creates exactly one fresh normal generation")
        check(h.config == originalConfiguration && h.store.state.snapshot!.usageLimitMinutes == 10,
              "Post-expiry recovery preserves the configured ten-minute budget")
        check(DashboardState(runtime: h.store.state).mode == .monitoring, "Valid post-expiry focus presents monitoring")
        check(h.selectionCountReports.last == ["applicationTokens": "4", "categoryTokens": "0", "webDomainTokens": "0", "result": "accepted"],
              "Start validation reports token counts only")
        print("VALIDATION four-app-only: applicationTokens=4 categoryTokens=0 webDomainTokens=0 result=accepted")
    }
    do {
        let h = Harness()
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4))
        try h.cooldown()
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4, webDomains: 1))
        h.time = h.store.state.cooldown!.endsAt
        fails { try h.sut.reconcile() }
        check(h.store.state.attention?.code == .selectionUnsupported && h.store.state.snapshot == nil,
              "Selection changed to four apps plus website is rejected at expiry")
        check(!h.shielded && h.store.state.cooldown == nil, "Unsupported replacement selection never strands elapsed cooldown")
        check(h.selectionCountReports.last?["webDomainTokens"] == "1" && h.selectionCountReports.last?["result"] == "rejected",
              "Actual rejected counts distinguish hidden websites from four-app-only selection")
        let attempts = h.scheduleAttempts
        for _ in 0..<3 { try h.sut.reconcile() }
        check(h.scheduleAttempts == attempts, "Invalid interrupted session is not automatically retried")
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4))
        try h.sut.start()
        check(h.store.state.attention == nil && h.store.state.snapshot != nil, "Correction plus explicit successful restart clears persisted failure")
        check(DashboardState(runtime: h.store.state).errorMessage == nil, "Corrected restart does not retain old selection error text")
        print("VALIDATION four-app-plus-website: applicationTokens=4 categoryTokens=0 webDomainTokens=1 result=rejected")
    }
    do {
        let h = Harness()
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4))
        try h.cooldown()
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4, webDomains: 1))
        fails { try h.sut.extendCooldown(minutes: 15) }
        check(h.store.state.attention?.code == .selectionUnsupported, "An earlier rejected attempt leaves historical selection attention")
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4))
        h.time = h.store.state.cooldown!.endsAt
        try h.sut.reconcile()
        check(h.store.state.snapshot != nil && h.store.state.attention == nil,
              "Successful post-expiry start supersedes stale selection attention even without shield ownership")
        check(DashboardState(runtime: h.store.state).mode == .monitoring, "Stale attention cannot falsely render successful expiry restart as failure")
        print("VALIDATION corrected-four-app-only: fresh focus accepted; stale selectionUnsupported cleared")
    }
    do {
        let h = Harness()
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4))
        h.store.state.attention = MonitoringAttention(code: .selectionUnsupported,
            occurredAt: h.time.addingTimeInterval(-240), activity: nil, message: SelectionFailure.unsupported.localizedDescription)
        let before = h.store.state
        try h.sut.reconcile()
        check(h.store.state == before && h.monitored.isEmpty, "Historical attention with inactive runtime does not silently start a new cycle")
        let state = DashboardState(runtime: h.store.state)
        check(state.mode == .failure && state.errorMessage!.contains("Previous selection issue"),
              "Persisted error is labelled historical instead of a fresh rejection")
        check(!state.canOfferInactiveStarts && !state.canConfigureDeepFocus && state.canRetryBreakLoop,
              "Verified interrupted runtime offers explicit Retry, not ordinary inactive Start modes")
        try h.sut.start()
        check(h.store.state.attention == nil && DashboardState(runtime: h.store.state).mode == .monitoring,
              "Device-shaped stale attention recovers after explicit four-app restart")
    }
    do {
        let h = Harness(); try h.cooldown()
        h.store.state.attention = MonitoringAttention(code: .selectionUnsupported, occurredAt: h.time,
            activity: nil, message: SelectionFailure.unsupported.localizedDescription)
        h.time = h.store.state.cooldown!.endsAt; h.failSchedule = true
        fails { try h.sut.reconcile() }
        check(h.store.state.attention?.code == .selectionUnsupported && h.store.state.snapshot == nil,
              "Failed focus restart never clears attention as if scheduling had succeeded")
    }
    do {
        let h = Harness(); h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4))
        try h.cooldown(); try h.sut.startDeepFocus(minutes: 60)
        let session = h.store.state.deepFocus!
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4, webDomains: 1))
        h.time = h.store.state.cooldown!.endsAt
        fails { try h.sut.reconcile() }
        check(h.shielded && h.store.state.deepFocus == session && h.store.state.cooldown == nil,
              "Selection correction path preserves independent Deep Focus ownership and deadline")
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4)); try h.sut.start()
        check(h.store.state.attention == nil && h.store.state.deepFocus == session && h.shielded,
              "Explicit normal recovery does not remove independent Deep Focus shield")
    }
    do {
        let good = SelectionTokenCounts(applicationTokens: 4, categoryTokens: 0, webDomainTokens: 0)
        let bad = SelectionTokenCounts(applicationTokens: 4, categoryTokens: 0, webDomainTokens: 1)
        check(good.isSupported && good.validationMessage == nil, "Picker and monitoring share four-app-only acceptance")
        check(!bad.isSupported && bad.validationMessage!.contains("1 websites"), "Picker explains website rejection before save/start")
        var saved = false
        fails { try bad.saveIfSupported { saved = true } }
        check(!saved && bad.webDomainTokens == 1, "Save gate neither persists nor silently strips unsupported websites")
        try good.saveIfSupported { saved = true }
        check(saved, "Valid corrected selection can be saved")
        check(SelectionTokenCounts(applicationTokens: 0, categoryTokens: 0, webDomainTokens: 0).validationMessage != nil,
              "Empty selection has actionable picker validation")
        check(!SelectionTokenCounts(applicationTokens: 51, categoryTokens: 0, webDomainTokens: 0).isSupported,
              "Token limits stay consistent with existing policy")
    }
    do {
        var runtime = MonitoringRuntime()
        runtime.snapshot = CycleSnapshot(configuration: .default)
        for state in [DashboardState(runtime: runtime, synchronizationError: "read failed"),
                      DashboardState(runtime: nil, synchronizationError: "read failed")] {
            check(state.mode == .failure && !state.canOfferInactiveStarts && !state.canConfigureDeepFocus && !state.canRetryBreakLoop,
                  "Unverified failure cannot offer any Start or Retry monitoring mode")
        }
        runtime.attention = MonitoringAttention(code: .selectionUnsupported, occurredAt: Date(), activity: nil,
                                               message: SelectionFailure.unsupported.localizedDescription)
        let current = DashboardState(runtime: runtime)
        check(current.mode == .failure && !current.canRetryBreakLoop && !current.canOfferInactiveStarts,
              "Persisted failure with a normal snapshot cannot assume monitoring inactive")
        check(current.canStopRecordedBreakLoop, "Verified recorded normal session has an explicit safe stop action")
        runtime.cooldown = RestrictionDeadline(endsAt: Date().addingTimeInterval(900))
        check(!DashboardState(runtime: runtime, synchronizationError: "failed").canRetryBreakLoop,
              "Failure retaining cooldown cannot offer a normal retry")
        runtime.deepFocus = DeepFocusSession(durationMinutes: 60)
        check(!DashboardState(runtime: runtime, synchronizationError: "failed").canConfigureDeepFocus,
              "Failure retaining Deep Focus cannot offer another Deep Focus start")
        check(DashboardState(runtime: MonitoringRuntime()).canOfferInactiveStarts, "Verified inactive presentation retains ordinary start actions")
    }
    do {
        let h = Harness(); h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4))
        try h.cooldown()
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4, webDomains: 1))
        h.time = h.store.state.cooldown!.endsAt
        var observations: [[String: String]] = []
        let sync = DashboardStateSynchronizer(read: { try h.store.readRuntime() }, reconcile: { try h.sut.reconcile() },
            observe: { _ in RuntimeCancellation {} }, schedule: { _, _ in RuntimeCancellation {} },
            now: { h.time }, publish: { _ in }, log: { _, metadata in observations.append(metadata) })
        sync.activate()
        check(sync.state.mode == .failure && sync.state.synchronizationError != nil && !sync.state.canRetryBreakLoop,
              "A fresh expiry rejection is distinguished from a historical persisted error")
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4))
        let attempts = h.scheduleAttempts
        sync.recover()
        check(sync.state.mode == .failure && sync.state.synchronizationError == nil && sync.state.canRetryBreakLoop,
              "Explicit refresh verifies interrupted ownership before exposing Retry")
        check(h.scheduleAttempts == attempts, "Selection correction and refresh do not silently restart interrupted monitoring")
        check(observations.last?["failureSource"] == "persisted_attention", "Diagnostics distinguish stale attention from current reconciliation failure")
        try h.sut.start(); sync.actionCompleted()
        check(sync.state.mode == .monitoring && sync.state.errorMessage == nil,
              "Successful corrected retry clears both persisted and transient synchronization errors")
        sync.deactivate()
    }
    do {
        let h = Harness(); try h.sut.start()
        h.store.state.attention = MonitoringAttention(code: .selectionUnsupported, occurredAt: h.time,
            activity: nil, message: SelectionFailure.unsupported.localizedDescription)
        check(DashboardState(runtime: h.store.state).canStopRecordedBreakLoop, "Previously active session with stale attention can be ended explicitly")
        try h.sut.stop()
        check(DashboardState(runtime: h.store.state).canRetryBreakLoop, "Stopping recorded normal ownership enables a safe reviewed retry")
        try h.sut.start()
        check(h.store.state.attention == nil, "Restart after explicit stop clears stale attention")
    }
    do {
        let h = Harness(); try h.cooldown()
        h.store.state.attention = MonitoringAttention(code: .selectionUnsupported, occurredAt: h.time,
            activity: nil, message: SelectionFailure.unsupported.localizedDescription)
        h.time = h.store.state.cooldown!.endsAt
        h.store.failedWritesRemaining = 1
        fails { try h.sut.reconcile() }
        check(h.store.state.snapshot == nil && h.store.state.attention?.code == .selectionUnsupported,
              "Failed fresh-cycle publication does not clear historical attention as if the restart committed")
        check(h.monitored.isEmpty && !h.shielded, "Publication failure leaves no orphan fresh focus or elapsed cooldown shield")
    }

}
