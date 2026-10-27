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

    func refresh() {
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
        let snapshot = CycleSnapshot(configuration: configuration)
        try? storage.saveActiveCycleSnapshot(snapshot)
        storage.clearUsageCheckpointState()
        storage.setBreakLoopActive(true)

        do {
            try deviceActivityService.startMonitoring(
                selection: selection,
                snapshot: snapshot
            )
            isBreakLoopActive = true
            activeSnapshot = snapshot
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopBreakLoop() {
        deviceActivityService.stopMonitoring()
        managedSettingsService.unblock()
        storage.clearUsageCheckpointState()
        storage.clearCooldownEndDate()
        storage.clearActiveCycleSnapshot()
        storage.setBreakLoopActive(false)

        isBreakLoopActive = false
        activeSnapshot = nil
    }

    func startDeepFocus(durationMinutes: Int) {
        guard hasSelection else {
            errorMessage = "Please select apps to block first."
            return
        }

        errorMessage = nil
        let session = DeepFocusSession(
            durationMinutes: durationMinutes
        )

        try? storage.saveDeepFocusSession(session)
        managedSettingsService.block(selection)

        do {
            try deviceActivityService.startDeepFocus(durationMinutes: durationMinutes)
            deepFocusSession = session
            isDeepFocusSheetPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopDeepFocus() {
        deviceActivityService.stopDeepFocus()
        storage.clearDeepFocusSession()
        deepFocusSession = nil

        // Deep focus bittiğinde eğer normal BreakLoop aktiftiyse kalkanı kaldırma yerine normal cycle'a dön
        if isBreakLoopActive {
            startBreakLoop()
        } else {
            managedSettingsService.unblock()
        }
    }

    func extendCooldown(by minutes: Int = 15) {
        guard let currentEnd = cooldownEndDate, isCooldownActive else { return }
        let newEnd = currentEnd.addingTimeInterval(TimeInterval(minutes * 60))
        try? storage.saveCooldownEndDate(newEnd)
        self.cooldownEndDate = newEnd
    }
}
