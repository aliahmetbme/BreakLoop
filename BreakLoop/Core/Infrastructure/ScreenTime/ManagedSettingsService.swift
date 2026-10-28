//
//  ManagedSettingsService.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import Foundation
import FamilyControls
import ManagedSettings

protocol ManagedSettingsServiceProtocol {
    func block(_ selection: FamilyActivitySelection)
    func unblock()
}

final class ManagedSettingsService: ManagedSettingsServiceProtocol {

    private let store: ManagedSettingsStore

    convenience init() {
        self.init(store: BreakLoopManagedSettings.makeStore())
    }

    init(store: ManagedSettingsStore) {
        self.store = store
    }

    // These setters have no enforcement acknowledgement API. A successful write only means
    // valid settings were requested; entitlement/authorization/device enforcement needs device QA.
    func block(_ selection: FamilyActivitySelection) {
        AppLogger.shared.record("shield_apply_attempted", category: .shield, outcome: "attempted",
            metadata: selection.breakLoopTokenCounts.diagnosticCounts.merging(["shieldAPIAttempted": "true"]) { value, _ in value })
        // Tek tek seçilmiş uygulamalar
        store.shield.applications =
            selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens

        // Seçilmiş kategoriler
        store.shield.applicationCategories =
            selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
    }

    func unblock() {
        AppLogger.shared.record("shield_clear_attempted", category: .shield, outcome: "attempted", metadata: ["shieldAPIAttempted": "true"])
        store.clearAllSettings()
    }
}
