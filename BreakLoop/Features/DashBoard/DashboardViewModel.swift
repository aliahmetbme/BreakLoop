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
    @Published var errorMessage: String?

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
            try action()
            errorMessage = nil
            synchronizer.actionCompleted()
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.error("dashboard_transition_failed", message: error.localizedDescription, category: .monitoring)
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
            if let savedSelection = try storage.loadActivitySelection() { selection = savedSelection }
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.error("dashboard_selection_read_failed", message: error.localizedDescription, category: .monitoring)
        }
    }

    var isCooldownActive: Bool { state.mode == .cooldown }
    var displayedError: String? { state.errorMessage ?? errorMessage }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
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
        guard hasSelection else {
            errorMessage = "Please select apps to monitor first."
            return
        }

        errorMessage = nil
        perform {
            try storage.saveActivitySelection(selection)
            try lifecycle.start()
        }
        refresh()
    }

    func stopBreakLoop() {
        perform { try lifecycle.stop() }
        refresh()
    }

    func startDeepFocus(durationMinutes: Int) {
        guard hasSelection else {
            errorMessage = "Please select apps to block first."
            return
        }

        errorMessage = nil
        perform {
            try storage.saveActivitySelection(selection)
            try lifecycle.startDeepFocus(minutes: durationMinutes)
            isDeepFocusSheetPresented = false
        }
        refresh()
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
