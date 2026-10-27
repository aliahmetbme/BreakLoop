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
    @Published var activeSnapshot: AppGroupStorage.CycleSnapshot?
    @Published var authorizationStatus: AuthorizationStatus

    private let storage: AppGroupStorage
    private let authorizationService: ScreenTimeAuthorizationServiceProtocol
    private let appearanceController: AppearanceController

    var appearance: AppAppearance {
        get { appearanceController.appearance }
        set { appearanceController.setAppearance(newValue) }
    }

    init(
        storage: AppGroupStorage = AppGroupStorage(),
        authorizationService: ScreenTimeAuthorizationServiceProtocol = ScreenTimeAuthorizationService(),
        appearanceController: AppearanceController = AppearanceController.shared
    ) {
        self.storage = storage
        self.authorizationService = authorizationService
        self.appearanceController = appearanceController
        self.authorizationStatus = authorizationService.authorizationStatus

        loadSettings()
    }

    func loadSettings() {
        let config = storage.loadCycleConfiguration()
        self.usageLimitMinutes = config.usageLimitMinutes
        self.restDurationMinutes = config.restDurationMinutes
        self.activeSnapshot = storage.loadActiveCycleSnapshot()
        self.authorizationStatus = authorizationService.authorizationStatus
    }

    func updateAppearance(_ newAppearance: AppAppearance) {
        appearanceController.setAppearance(newAppearance)
    }

    func updateUsageLimit(_ minutes: Int) {
        let clamped = max(
            AppGroupStorage.CycleConfiguration.minUsageMinutes,
            min(AppGroupStorage.CycleConfiguration.maxUsageMinutes, minutes)
        )
        usageLimitMinutes = clamped
        saveConfiguration()
    }

    func updateRestDuration(_ minutes: Int) {
        let clamped = max(
            AppGroupStorage.CycleConfiguration.minRestMinutes,
            min(AppGroupStorage.CycleConfiguration.maxRestMinutes, minutes)
        )
        restDurationMinutes = clamped
        saveConfiguration()
    }

    func resetToDefaults() {
        let defaultConfig = AppGroupStorage.CycleConfiguration.default
        usageLimitMinutes = defaultConfig.usageLimitMinutes
        restDurationMinutes = defaultConfig.restDurationMinutes
        saveConfiguration()
    }

    private func saveConfiguration() {
        let config = AppGroupStorage.CycleConfiguration(
            usageLimitMinutes: usageLimitMinutes,
            restDurationMinutes: restDurationMinutes
        )
        try? storage.saveCycleConfiguration(config)
    }
}
