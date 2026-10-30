//
//  BreakLoopApp.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import SwiftUI
#if DEBUG
import FamilyControls
final class MockAuthorizedService: ScreenTimeAuthorizationServiceProtocol {
    var authorizationStatus: AuthorizationStatus = .approved
    func requestAuthorization() async throws {}
}
#endif

@main
struct BreakLoopApp: App {

    init() { AppLogger.shared.record("app_launched", category: .lifecycle) }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CommandLine.arguments.contains("-testDashboard") {
                DashboardView()
                    .environmentObject(AppearanceController.shared)
            } else {
                AppRootView()
            }
            #else
            AppRootView()
            #endif
        }
    }
}
