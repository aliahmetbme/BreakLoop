//
//  DashboardViewModel.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import Foundation
import Combine
import FamilyControls

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published private(set) var state = DashboardState.loading
    @Published var configuration: CycleConfiguration = .default
    var activeSnapshot: CycleSnapshot? { state.runtime?.snapshot }
    var isBreakLoopActive: Bool { state.runtime?.snapshot != nil && state.mode != .failure }
    var deepFocusSession: DeepFocusSession? { state.runtime?.deepFocus }
    var cooldownEndDate: Date? { state.runtime?.cooldown?.endsAt }
    var isDeepFocusActive: Bool { state.mode == .deepFocus }
    var canStopBreakLoop: Bool { state.canStopBreakLoop }
    @Published var selection = FamilyActivitySelection()
    @Published var isDeepFocusSheetPresented: Bool = false
    @Published var deepFocusErrorMessage: String?
    @Published private(set) var isStartingDeepFocus: Bool = false
    @Published var errorMessage: String?
    private var selectionReadError: String?
    private let deepFocusLauncher = DeepFocusLaunchController()

    private let storage: AppGroupStorage
    private let deviceActivityService: DeviceActivityServiceProtocol
    private let managedSettingsService: ManagedSettingsServiceProtocol

    init() {
        self.storage = AppGroupStorage()
        self.deviceActivityService = DeviceActivityService()
        self.managedSettingsService = ManagedSettingsService()

        refresh()
    }

    init(
        storage: AppGroupStorage,
        deviceActivityService: DeviceActivityServiceProtocol,
        managedSettingsService: ManagedSettingsServiceProtocol
    ) {
        self.storage = storage
        self.deviceActivityService = deviceActivityService
        self.managedSettingsService = managedSettingsService

        refresh()
    }

    private lazy var synchronizer = DashboardStateSynchronizer(
        read: { [storage] in try storage.readRuntime() },
        reconcile: { [storage, deviceActivityService, managedSettingsService] in
            try MonitoringLifecycle.make(storage: storage, activity: deviceActivityService,
                                         settings: managedSettingsService).reconcile()
        },
        observe: { changed in
            try RuntimeChangeSignal.observe { Task { @MainActor in changed() } }
        },
        publish: { [weak self] in self?.state = $0 },
        log: { event, metadata in
            AppLogger.shared.info(event,
                message: "Dashboard read: \(metadata["reason"] ?? "unknown"), mode=\(metadata["mode"] ?? "unknown"), cooldown=\(metadata["cooldownId"] ?? "none"), observedAt=\(metadata["observedAtEpoch"] ?? "unknown").",
                category: .monitoring, metadata: metadata)
        })

    func activate() {
        refreshConfiguration()
        synchronizer.activate()
    }

    func deactivate() { synchronizer.deactivate() }

    private var lifecycle: MonitoringLifecycle {
        .make(storage: storage, activity: deviceActivityService, settings: managedSettingsService)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try AppLogger.shared.withOperation("dashboard_action", action)
            errorMessage = nil
            synchronizer.actionCompleted()
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.failure("dashboard_transition_failed", error: error, category: .monitoring)
        }
    }

    // Read-only: sheet dismissal, notifications and UI refresh never reconcile or reschedule.
    func refresh() {
        refreshConfiguration()
        synchronizer.refresh()
    }

    private func refreshConfiguration() {
        configuration = storage.loadCycleConfiguration()
        do {
            if let savedSelection = try storage.loadActivitySelection() {
                selection = savedSelection
                savedSelection.logBreakLoopCounts(stage: "dashboard_read")
            } else {
                selection = FamilyActivitySelection()
            }
            selectionReadError = nil
        } catch {
            selectionReadError = error.localizedDescription
            AppLogger.shared.failure("dashboard_selection_read_failed", error: error, category: .monitoring)
        }
    }

    var isCooldownActive: Bool { state.mode == .cooldown }
    var displayedError: String? { state.errorMessage ?? selectionReadError ?? errorMessage }

    var selectionState: DashboardSelectionState {
        DashboardSelectionState(counts: selection.breakLoopTokenCounts, readError: selectionReadError)
    }

    var experiencePresentation: DashboardExperiencePresentation {
        DashboardExperiencePresentation(mode: state.mode, selection: selectionState)
    }

    var hasSelection: Bool { selectionState.isSupported }
    var hasAnySelection: Bool { selection.breakLoopTokenCounts.hasAny }
    var selectionIssue: String? { selectionState.validationOrReadErrorMessage }
    var selectedWebsitesCount: Int { selection.webDomainTokens.count }

    var canOfferDeepFocus: Bool { state.canConfigureDeepFocus && hasSelection }
    var focusCompanionState: DashboardFocusCompanionState { DashboardFocusCompanionState(state: state) }

    func presentDeepFocusSheet() {
        guard canOfferDeepFocus, !isStartingDeepFocus, !isDeepFocusSheetPresented else { return }
        deepFocusLauncher.presentSheet()
        deepFocusErrorMessage = deepFocusLauncher.errorMessage
        isDeepFocusSheetPresented = deepFocusLauncher.isSheetPresented
    }

    func dismissDeepFocusSheet() {
        deepFocusLauncher.dismissSheet()
        deepFocusErrorMessage = deepFocusLauncher.errorMessage
        isDeepFocusSheetPresented = deepFocusLauncher.isSheetPresented
    }

    func recoverSynchronization() {
        refreshConfiguration()
        synchronizer.recover()
    }

    private func loadSupportedSelection() throws {
        guard let current = try storage.loadActivitySelection() else { throw SelectionFailure.missing }
        selection = current
        current.logBreakLoopCounts(stage: "dashboard_start")
        guard current.breakLoopTokenCounts.isSupported else { throw SelectionFailure.unsupported }
    }

    var selectedAppsCount: Int {
        selection.applicationTokens.count
    }

    var selectedCategoriesCount: Int {
        selection.categoryTokens.count
    }

    var effectiveLimitMinutes: Int {
        activeSnapshot?.usageLimitMinutes ?? configuration.usageLimitMinutes
    }

    var effectiveRestMinutes: Int {
        activeSnapshot?.restDurationMinutes ?? configuration.restDurationMinutes
    }

    func startBreakLoop() {
        guard state.mode != .failure || state.canRetryBreakLoop else {
            errorMessage = state.recoveryDescription; return
        }
        errorMessage = nil
        perform {
            try loadSupportedSelection()
            try lifecycle.start()
        }
        refresh()
    }

    func stopBreakLoop() {
        perform { try lifecycle.stop() }
        refresh()
    }

    @discardableResult
    func startDeepFocus(durationMinutes: Int) -> Bool {
        guard !isStartingDeepFocus else { return false }
        isStartingDeepFocus = true
        defer { isStartingDeepFocus = false }
        errorMessage = nil
        let started = deepFocusLauncher.start(
            durationMinutes: durationMinutes,
            canConfigure: state.canConfigureDeepFocus
        ) { [weak self] minutes in
            guard let self else { throw LifecycleError.transitionCancelled }
            do {
                try AppLogger.shared.withOperation("dashboard_action") {
                    try self.loadSupportedSelection()
                    try self.lifecycle.startDeepFocus(minutes: minutes)
                }
            } catch {
                AppLogger.shared.failure("dashboard_transition_failed", error: error, category: .monitoring)
                throw error
            }
        }
        deepFocusErrorMessage = deepFocusLauncher.errorMessage
        if started {
            isDeepFocusSheetPresented = false
            synchronizer.actionCompleted()
        }
        refresh()
        return started
    }

    func stopDeepFocus() {
        perform { try lifecycle.stopDeepFocus() }
        refresh()
    }

    func extendCooldown(by minutes: Int = 15) {
        perform { try lifecycle.extendCooldown(minutes: minutes) }
        refresh()
    }
}
