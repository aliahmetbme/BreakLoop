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

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: AppRootViewModel
    @ObservedObject private var appearanceController = AppearanceController.shared

    init() {
        _viewModel = StateObject(wrappedValue: AppRootViewModel())
    }

    init(viewModel: AppRootViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init(authorizationService: ScreenTimeAuthorizationServiceProtocol) {
        let vm = AppRootViewModel(
            authorizationService: authorizationService,
            deviceActivityService: DeviceActivityService(),
            managedSettingsService: ManagedSettingsService(),
            storage: AppGroupStorage()
        )
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        Group {
            switch viewModel.uiState {
            case .authorized:
                DashboardView()

            case .firstTimeOnboarding:
                OnboardingView(onAuthorized: {
                    viewModel.handleSceneActive()
                })

            case .permissionRevoked(let isDeniedInSettings):
                PermissionRequiredView(
                    isDeniedInSettings: isDeniedInSettings,
                    isRequesting: viewModel.isRequestingAuthorization,
                    errorMessage: viewModel.errorMessage,
                    onAllowAccess: {
                        Task {
                            await viewModel.requestAuthorization()
                        }
                    },
                    onOpenSettings: {
                        viewModel.openSettings()
                    }
                )
            }
        }
        .preferredColorScheme(appearanceController.appearance.colorScheme)
        .tint(BLColor.brandPrimary)
        .environmentObject(appearanceController)
        .onAppear {
            viewModel.handleSceneActive()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.handleSceneActive()
            }
        }
    }
}
