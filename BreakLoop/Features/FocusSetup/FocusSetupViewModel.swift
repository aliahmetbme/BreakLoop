//
//  FocusSetupViewModel.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import Foundation
import FamilyControls
import Combine

@MainActor
final class FocusSetupViewModel: ObservableObject {

    @Published var selection = FamilyActivitySelection()
    @Published var usageLimitMinutes: Int = 20
    @Published var restDurationMinutes: Int = 15
    @Published var isPickerPresented = false
    @Published var errorMessage: String?

    private let storage: AppGroupStorage
    private let managedSettingsService: ManagedSettingsServiceProtocol
    private let deviceActivityService: DeviceActivityServiceProtocol

    init(
        storage: AppGroupStorage,
        managedSettingsService: ManagedSettingsServiceProtocol,
        deviceActivityService: DeviceActivityServiceProtocol
    ) {
        self.storage = storage
        self.managedSettingsService = managedSettingsService
        self.deviceActivityService = deviceActivityService

        loadSelection()
    }

    @MainActor
    static func makeDefault() -> FocusSetupViewModel {
        FocusSetupViewModel(
            storage: AppGroupStorage(),
            managedSettingsService: ManagedSettingsService(),
            deviceActivityService: DeviceActivityService()
        )
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }

    func saveConfiguration() {
        saveSelection()
        let config = CycleConfiguration(
            usageLimitMinutes: usageLimitMinutes,
            restDurationMinutes: restDurationMinutes
        )
        do {
            try storage.saveCycleConfiguration(config)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSelection() {
        do {
            try storage.saveActivitySelection(selection)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func blockSelection() {
        guard hasSelection else {
            return
        }

        managedSettingsService.block(selection)
    }

    func unblockSelection() {
        managedSettingsService.unblock()
    }

    func startMonitoring() {
        guard hasSelection else {
            return
        }

        errorMessage = nil
        do {
            try storage.saveActivitySelection(selection)
            try MonitoringLifecycle.make(storage: storage, activity: deviceActivityService,
                                         settings: managedSettingsService).start()
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.error("setup_start_failed", message: error.localizedDescription, category: .monitoring)
        }
    }

    func stopMonitoring() {
        do {
            try MonitoringLifecycle.make(storage: storage, activity: deviceActivityService,
                                         settings: managedSettingsService).stop()
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.error("setup_stop_failed", message: error.localizedDescription, category: .monitoring)
        }
    }

    private func loadSelection() {
        let config = storage.loadCycleConfiguration()
        usageLimitMinutes = config.usageLimitMinutes
        restDurationMinutes = config.restDurationMinutes

        do {
            if let savedSelection = try storage.loadActivitySelection() {
                selection = savedSelection
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
