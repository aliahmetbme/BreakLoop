//
//  SettingsViewModel.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import Foundation
import Combine
import FamilyControls

@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var usageLimitMinutes: Int = 20
    @Published var restDurationMinutes: Int = 15
    @Published var activeSnapshot: CycleSnapshot?
    @Published var authorizationStatus: AuthorizationStatus
    @Published var errorMessage: String?

    private let storage: AppGroupStorage
    private let authorizationService: ScreenTimeAuthorizationServiceProtocol
    private let appearanceController: AppearanceController
    private let persistConfiguration: (CycleConfiguration) throws -> Void
    private var saveController = ConfigurationSaveController()

    var committedConfiguration: CycleConfiguration { saveController.committed }
    var hasUnsavedChanges: Bool { saveController.hasUnsavedChanges }

    var appearance: AppAppearance {
        get { appearanceController.appearance }
        set { appearanceController.setAppearance(newValue) }
    }

    init(
        storage: AppGroupStorage = AppGroupStorage(),
        authorizationService: ScreenTimeAuthorizationServiceProtocol = ScreenTimeAuthorizationService(),
        appearanceController: AppearanceController = AppearanceController.shared,
        persistConfiguration: ((CycleConfiguration) throws -> Void)? = nil
    ) {
        self.storage = storage
        self.authorizationService = authorizationService
        self.appearanceController = appearanceController
        self.persistConfiguration = persistConfiguration ?? { config in
            try storage.saveCycleConfiguration(config)
        }
        self.authorizationStatus = authorizationService.authorizationStatus

        loadSettings()
    }

    func loadSettings() {
        let config = storage.loadCycleConfiguration()
        saveController.reload(committed: config)
        self.usageLimitMinutes = config.usageLimitMinutes
        self.restDurationMinutes = config.restDurationMinutes
        self.errorMessage = nil
        self.activeSnapshot = storage.loadActiveCycleSnapshot()
        self.authorizationStatus = authorizationService.authorizationStatus
    }

    func updateAppearance(_ newAppearance: AppAppearance) {
        appearanceController.setAppearance(newAppearance)
    }

    func updateUsageLimit(_ minutes: Int) {
        saveController.setUsageLimit(minutes)
        usageLimitMinutes = saveController.pending.usageLimitMinutes
        saveConfiguration()
    }

    func updateRestDuration(_ minutes: Int) {
        saveController.setRestDuration(minutes)
        restDurationMinutes = saveController.pending.restDurationMinutes
        saveConfiguration()
    }

    func resetToDefaults() {
        let defaultConfig = CycleConfiguration.default
        saveController.setUsageLimit(defaultConfig.usageLimitMinutes)
        saveController.setRestDuration(defaultConfig.restDurationMinutes)
        usageLimitMinutes = saveController.pending.usageLimitMinutes
        restDurationMinutes = saveController.pending.restDurationMinutes
        saveConfiguration()
    }

    func revertUnsavedChanges() {
        saveController.revertPendingToCommitted()
        usageLimitMinutes = saveController.committed.usageLimitMinutes
        restDurationMinutes = saveController.committed.restDurationMinutes
        errorMessage = nil
    }

    @discardableResult
    func saveConfiguration() -> Bool {
        saveController.setUsageLimit(usageLimitMinutes)
        saveController.setRestDuration(restDurationMinutes)
        var capturedError: Error?
        let saved = saveController.save { config in
            do {
                try persistConfiguration(config)
            } catch {
                capturedError = error
                throw error
            }
        }
        errorMessage = saveController.errorMessage
        if let capturedError {
            AppLogger.shared.failure("settings_configuration_save_failed", error: capturedError, category: .selection)
        }
        return saved
    }
}
