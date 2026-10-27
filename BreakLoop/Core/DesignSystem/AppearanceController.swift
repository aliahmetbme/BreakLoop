//
//  AppearanceController.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI
import Combine

@MainActor
final class AppearanceController: ObservableObject {

    static let shared = AppearanceController()

    @Published var appearance: AppAppearance

    private let storage: AppGroupStorage

    init(storage: AppGroupStorage = AppGroupStorage()) {
        self.storage = storage
        self.appearance = storage.loadAppearance()
    }

    func setAppearance(_ newAppearance: AppAppearance) {
        guard appearance != newAppearance else { return }
        self.appearance = newAppearance
        storage.saveAppearance(newAppearance)
    }
}
