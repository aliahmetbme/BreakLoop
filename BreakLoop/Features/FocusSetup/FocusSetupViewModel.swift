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
        let config = AppGroupStorage.CycleConfiguration(
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

        saveSelection()
        storage.clearUsageCheckpointState()

        let configuration = storage.loadCycleConfiguration()
        let snapshot = AppGroupStorage.CycleSnapshot(configuration: configuration)
        try? storage.saveActiveCycleSnapshot(snapshot)
        storage.setBreakLoopActive(true)

        do {
            try deviceActivityService.startMonitoring(
                selection: selection,
                snapshot: snapshot
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopMonitoring() {
        deviceActivityService.stopMonitoring()
        managedSettingsService.unblock()
        storage.clearUsageCheckpointState()
        storage.clearCooldownEndDate()
        storage.clearActiveCycleSnapshot()
        storage.setBreakLoopActive(false)
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
