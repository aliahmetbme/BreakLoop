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

    @Published var isBreakLoopActive: Bool = false
    @Published var deepFocusSession: DeepFocusSession?
    @Published var cooldownEndDate: Date?
    @Published var configuration: CycleConfiguration = .default
    @Published var activeSnapshot: CycleSnapshot?
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

    private var lifecycle: MonitoringLifecycle {
        .make(storage: storage, activity: deviceActivityService, settings: managedSettingsService)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.error("dashboard_transition_failed", message: error.localizedDescription, category: .monitoring)
        }
    }

    func refresh() {
        perform { try lifecycle.reconcile() }
        self.configuration = storage.loadCycleConfiguration()
        self.activeSnapshot = storage.loadActiveCycleSnapshot()
        self.isBreakLoopActive = storage.isBreakLoopActive()
        self.deepFocusSession = storage.loadDeepFocusSession()
        self.cooldownEndDate = try? storage.loadCooldownEndDate()

        if let savedSelection = try? storage.loadActivitySelection() {
            self.selection = savedSelection
        }
    }

    var isCooldownActive: Bool {
        guard let cooldownEndDate = cooldownEndDate else { return false }
        return Date() < cooldownEndDate
    }

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
