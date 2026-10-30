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
    @Published var usageLimitMinutes: Int = 20 {
        didSet { saveController.setUsageLimit(usageLimitMinutes) }
    }
    @Published var restDurationMinutes: Int = 15 {
        didSet { saveController.setRestDuration(restDurationMinutes) }
    }
    @Published var isPickerPresented = false
    @Published var errorMessage: String?

    private let storage: AppGroupStorage
    private let managedSettingsService: ManagedSettingsServiceProtocol
    private let deviceActivityService: DeviceActivityServiceProtocol
    private var saveController = ConfigurationSaveController()

    var committedConfiguration: CycleConfiguration { saveController.committed }
    var hasUnsavedConfigurationChanges: Bool { saveController.hasUnsavedChanges }

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

    var selectionIssue: String? { selection.breakLoopTokenCounts.validationMessage }
    var hasSelection: Bool { selection.breakLoopTokenCounts.isSupported }

    @discardableResult
    func saveConfiguration() -> Bool {
        saveController.setUsageLimit(usageLimitMinutes)
        saveController.setRestDuration(restDurationMinutes)
        let saved = saveController.save(selectionCounts: selection.breakLoopTokenCounts) { [storage, selection] config in
            try storage.saveActivitySelection(selection)
            try storage.saveCycleConfiguration(config)
        }
        errorMessage = saveController.errorMessage
        if saved {
            usageLimitMinutes = saveController.committed.usageLimitMinutes
            restDurationMinutes = saveController.committed.restDurationMinutes
        } else if let err = errorMessage {
            AppLogger.shared.info("setup_save_rejected", message: "FocusSetup save failed: \(err)", category: .selection)
        }
        return saved
    }

    @discardableResult
    func saveSelection() -> Bool {
        guard hasSelection else { errorMessage = selectionIssue; return false }
        do {
            try storage.saveActivitySelection(selection)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.failure("setup_selection_save_failed", error: error, category: .selection)
            return false
        }
    }

    func blockSelection() {
        guard hasSelection else { errorMessage = selectionIssue; return }
        managedSettingsService.block(selection)
    }

    func unblockSelection() {
        managedSettingsService.unblock()
    }

    func startMonitoring() {
        guard hasSelection else { errorMessage = selectionIssue; return }
        errorMessage = nil
        do {
            try storage.saveActivitySelection(selection)
            try MonitoringLifecycle.make(storage: storage, activity: deviceActivityService,
                                         settings: managedSettingsService).start()
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.failure("setup_start_failed", error: error, category: .monitoring)
        }
    }

    func stopMonitoring() {
        do {
            try MonitoringLifecycle.make(storage: storage, activity: deviceActivityService,
                                         settings: managedSettingsService).stop()
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.failure("setup_stop_failed", error: error, category: .monitoring)
        }
    }

    private func loadSelection() {
        let config = storage.loadCycleConfiguration()
        saveController.reload(committed: config)
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
