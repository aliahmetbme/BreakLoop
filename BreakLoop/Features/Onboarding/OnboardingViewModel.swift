//
//  Untitled.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import Combine
import Foundation
import FamilyControls

@MainActor
final class OnboardingViewModel: ObservableObject {

    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published private(set) var isRequestingAuthorization = false
    @Published var errorMessage: String?

    private let authorizationService:
        ScreenTimeAuthorizationServiceProtocol

    init(
        authorizationService:
            ScreenTimeAuthorizationServiceProtocol
    ) {
        self.authorizationService = authorizationService
        self.authorizationStatus =
            authorizationService.authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .approved
    }

    func requestAuthorization() async {
        guard !isRequestingAuthorization else {
            return
        }

        isRequestingAuthorization = true
        errorMessage = nil

        defer {
            isRequestingAuthorization = false
        }

        do {
            try await authorizationService.requestAuthorization()

            authorizationStatus =
                authorizationService.authorizationStatus

        } catch {
            authorizationStatus =
                authorizationService.authorizationStatus

            errorMessage = error.localizedDescription
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus =
            authorizationService.authorizationStatus
    }
}
