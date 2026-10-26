//
//  AppRootView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI
import FamilyControls

@MainActor
struct AppRootView: View {

    @State private var isAuthorized: Bool = false
    private let authorizationService: ScreenTimeAuthorizationServiceProtocol

    init() {
        let service = ScreenTimeAuthorizationService()
        self.authorizationService = service
        _isAuthorized = State(initialValue: service.authorizationStatus == .approved)
    }

    init(
        authorizationService: ScreenTimeAuthorizationServiceProtocol
    ) {
        self.authorizationService = authorizationService
        _isAuthorized = State(initialValue: authorizationService.authorizationStatus == .approved)
    }

    var body: some View {
        Group {
            if isAuthorized {
                DashboardView()
            } else {
                OnboardingView(onAuthorized: {
                    withAnimation {
                        isAuthorized = true
                    }
                })
            }
        }
        .onAppear {
            checkAuthorization()
        }
    }

    private func checkAuthorization() {
        isAuthorized = (authorizationService.authorizationStatus == .approved)
    }
}
