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
    @Published var isPickerPresented = false
    @Published var errorMessage: String?
    
    private let storage: AppGroupStorage

    init(
        storage: AppGroupStorage = AppGroupStorage()
    ) {
        self.storage = storage
        loadSelection()
    }
    
    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }
    
    func saveSelection() {
            do {
                try storage.saveActivitySelection(selection)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

    private func loadSelection() {
            do {
                if let savedSelection =
                    try storage.loadActivitySelection() {

                    selection = savedSelection
                }
            } catch {
                errorMessage = error.localizedDescription
            }
    }

}
