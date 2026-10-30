import Foundation

@MainActor func runDeepFocusCoexistenceTests() throws {
    do {
        let h = Harness(); try h.sut.start()
        let snapshot = h.store.state.snapshot!
        let checkpoint = UsageCheckpointState(usageMinute: 4, timestamp: h.time)
        h.store.state.checkpoint = checkpoint
        let selection = h.selectionData
        let configuration = h.config
        let normal = MonitoringRuntime.focusName(snapshot.id)
        let schedules = h.scheduleAttempts
        try h.sut.startDeepFocus(minutes: 15)
        check(h.store.state.snapshot == snapshot, "Focus start preserves exact normal snapshot, start date and limits")
        check(h.store.state.checkpoint == checkpoint, "Focus start preserves usage checkpoint")
        check(h.config == configuration && h.selectionData == selection, "Focus start does not change saved configuration or selection")
        check(h.monitored.contains(normal) && h.monitored.count == 2 && h.scheduleAttempts == schedules + 1,
              "Focus adds only its deadline; normal monitoring is neither stopped nor restarted")
        check(DashboardFocusCompanionState(state: DashboardState(runtime: h.store.state)) == .usageCycle,
              "Coexisting focus communicates its underlying cycle without a second timer")
        let session = h.store.state.deepFocus!
        h.time = h.time.addingTimeInterval(30)
        try h.sut.reconcile() // Same reconciliation used on foreground.
        check(h.store.state.snapshot == snapshot && h.store.state.checkpoint == checkpoint && h.store.state.deepFocus == session,
              "Foreground reconcile preserves both activities and checkpoint")
        let encoded = try JSONEncoder().encode(h.store.state)
        let restored = try JSONDecoder().decode(MonitoringRuntime.self, from: encoded)
        check(restored == h.store.state && DashboardState(runtime: restored).mode == .deepFocus,
              "Persisted coexistence decodes after relaunch with focus foregrounded")
        let attempts = h.scheduleAttempts
        try h.sut.stopDeepFocus()
        check(h.store.state.snapshot == snapshot && h.store.state.checkpoint == checkpoint, "Early end preserves the original allowance and checkpoint")
        check(DashboardState(runtime: h.store.state).mode == .monitoring && h.monitored == [normal],
              "Early end returns to the existing normal monitor")
        check(h.scheduleAttempts == attempts, "Early focus end does not create a fresh normal generation")
        try h.sut.startDeepFocus(minutes: 15)
        let expiration = h.store.state.deepFocus!
        h.time = expiration.endsAt
        try h.sut.intervalEnded(name: MonitoringRuntime.deepFocusName(expiration.id))
        check(h.store.state.deepFocus == nil && h.store.state.snapshot == snapshot && h.store.state.checkpoint == checkpoint,
              "Natural focus expiry preserves the normal snapshot and checkpoint")
        check(DashboardState(runtime: h.store.state).mode == .monitoring && h.monitored == [normal],
              "Natural focus expiry never blindly reports inactive")
        try h.sut.intervalEnded(name: MonitoringRuntime.deepFocusName(session.id))
        check(h.store.state.snapshot == snapshot && h.store.state.checkpoint == checkpoint, "Delayed old focus callback cannot reset normal allowance")
    }
    do {
        let h = Harness(); try h.sut.start()
        let snapshot = h.store.state.snapshot!
        try h.sut.threshold(name: MonitoringRuntime.focusName(snapshot.id), minute: 2)
        let checkpoint = h.store.state.checkpoint
        try h.sut.startDeepFocus(minutes: 60)
        let session = h.store.state.deepFocus!
        let beforeThreshold = h.scheduleAttempts
        try h.sut.threshold(name: MonitoringRuntime.focusName(snapshot.id), minute: nil)
        let cooldown = h.store.state.cooldown!
        check(h.store.state.snapshot == snapshot && h.store.state.deepFocus == session && h.shielded,
              "Usage threshold still starts normal cooldown while focus is active")
        check(h.store.state.checkpoint == nil && checkpoint != nil, "Threshold keeps its existing checkpoint-consumption semantics; focus does not freeze it")
        check(h.scheduleAttempts == beforeThreshold + 1, "Threshold creates only the normal cooldown deadline")
        check(DashboardFocusCompanionState(state: DashboardState(runtime: h.store.state)) == .cooldown,
              "Foregrounded focus communicates an independently owned break")
        let clears = h.clears
        try h.sut.stopDeepFocus()
        check(h.store.state.cooldown == cooldown && h.shielded && h.clears == clears,
              "Early focus end never clears an active cooldown shield")
        check(DashboardState(runtime: h.store.state).mode == .cooldown, "Focus early end returns to cooldown, not inactive")
        check(!DashboardState(runtime: h.store.state).canConfigureDeepFocus, "Dashboard still prevents new focus launches during cooldown")
    }
    do {
        let h = Harness(); try h.sut.start(); try h.sut.startDeepFocus(minutes: 15)
        h.time = h.time.addingTimeInterval(60)
        try h.sut.threshold(name: MonitoringRuntime.focusName(h.store.state.snapshot!.id), minute: nil)
        let cooldown = h.store.state.cooldown!
        let focus = h.store.state.deepFocus!
        h.time = focus.endsAt
        let clears = h.clears
        try h.sut.intervalEnded(name: MonitoringRuntime.deepFocusName(focus.id))
        check(h.store.state.deepFocus == nil && h.store.state.cooldown == cooldown && h.shielded && h.clears == clears,
              "Natural focus expiry before cooldown expiry retains cooldown ownership")
    }
    do {
        let h = Harness(); try h.sut.start()
        h.store.state.checkpoint = UsageCheckpointState(usageMinute: 3, timestamp: h.time)
        let before = h.store.state
        let names = h.monitored
        let clears = h.clears
        h.failSchedule = true
        fails { try h.sut.startDeepFocus(minutes: 60) }
        check(h.store.state == before && h.monitored == names && h.clears == clears,
              "Scheduling failure during normal cycle leaves exact runtime and shield state unchanged")
        h.failSchedule = false
        try h.sut.startDeepFocus(minutes: 60)
        check(h.store.state.snapshot == before.snapshot && h.store.state.checkpoint == before.checkpoint,
              "Explicit safe retry preserves original cycle and checkpoint")
        let focus = h.store.state.deepFocus!
        h.monitored.removeAll { $0 == MonitoringRuntime.focusName(before.snapshot!.id) }
        fails { try h.sut.reconcile() }
        check(h.store.state.snapshot == nil && h.store.state.deepFocus == focus && h.shielded,
              "A genuinely missing normal monitor recovers rather than pretending the original cycle is valid")
        check(DashboardFocusCompanionState(state: DashboardState(runtime: h.store.state)) == .none,
              "Invalidated cycle is not advertised as active behind focus")
        try h.sut.stopDeepFocus()
        check(DashboardState(runtime: h.store.state).mode == .failure, "Focus ending over interrupted normal runtime returns recovery UI")
    }
    do {
        let h = Harness(); try h.sut.start()
        let snapshot = h.store.state.snapshot!
        h.onStart = { name in
            guard name.hasPrefix("breakloop.deepFocus.") else { return }
            try! h.sut.intervalStarted(name: name)
            try! h.sut.threshold(name: MonitoringRuntime.focusName(snapshot.id), minute: 2)
            fails { try h.sut.startDeepFocus(minutes: 30) }
        }
        let attempts = h.scheduleAttempts
        try h.sut.startDeepFocus(minutes: 60)
        check(h.scheduleAttempts == attempts + 1 && h.monitored.count == 2 && h.store.state.pendingTransition == nil,
              "Reentrant duplicate start and delayed callbacks produce one focus generation")
        check(h.store.state.snapshot == snapshot && h.store.state.checkpoint?.usageMinute == 2,
              "Deferred normal usage callbacks advance the original checkpoint without a reset or freeze")
        h.selectionData = try JSONEncoder().encode(TestSelection(applications: 4, categories: 0, webDomains: 1))
        let old = h.store.state
        fails { try h.sut.startDeepFocus(minutes: 30) }
        check(h.store.state.snapshot == old.snapshot && h.store.state.checkpoint == old.checkpoint && h.store.state.deepFocus == old.deepFocus && h.shielded,
              "Unsupported selection cannot replace focus or discard the active cycle")
        try h.sut.stop(all: true) // Existing authorization-revocation cleanup.
        check(h.store.state.snapshot == nil && h.store.state.deepFocus == nil && h.store.state.cooldown == nil && !h.shielded && h.monitored.isEmpty,
              "Existing genuine-revocation cleanup still clears both owners")
    }
}
