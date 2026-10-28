//
//  AppRootViewModel.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import Foundation
import Combine
import FamilyControls
import UIKit

@MainActor
final class AppRootViewModel: ObservableObject {

    @Published var uiState: AuthorizationUIState
    @Published var isRequestingAuthorization: Bool = false
    @Published var errorMessage: String?

    private var lastKnownStatus: AuthorizationStatus?
    private let authorizationService: ScreenTimeAuthorizationServiceProtocol
    private let deviceActivityService: DeviceActivityServiceProtocol
    private let managedSettingsService: ManagedSettingsServiceProtocol
    private let storage: AppGroupStorage

    convenience init() {
        self.init(
            authorizationService: ScreenTimeAuthorizationService(),
            deviceActivityService: DeviceActivityService(),
            managedSettingsService: ManagedSettingsService(),
            storage: AppGroupStorage()
        )
    }

    init(
        authorizationService: ScreenTimeAuthorizationServiceProtocol,
        deviceActivityService: DeviceActivityServiceProtocol,
        managedSettingsService: ManagedSettingsServiceProtocol,
        storage: AppGroupStorage
    ) {
        self.authorizationService = authorizationService
        self.deviceActivityService = deviceActivityService
        self.managedSettingsService = managedSettingsService
        self.storage = storage

        let initialStatus = authorizationService.authorizationStatus
        self.lastKnownStatus = initialStatus
        self.uiState = AuthorizationStateEvaluator.evaluate(
            status: initialStatus,
            hasPreviouslyConfigured: storage.hasConfiguredSelection()
        )
    }

    // Root and visible Dashboard share one synchronizer. Activation is idempotent, so
    // foreground recovery also works while a settings/navigation screen covers the Dashboard.
    private(set) lazy var dashboardViewModel = DashboardViewModel(
        storage: storage, deviceActivityService: deviceActivityService,
        managedSettingsService: managedSettingsService)

    func handleSceneInactive() {
        if uiState == .authorized { dashboardViewModel.deactivate() }
    }

    func handleSceneActive() {
        let currentStatus = authorizationService.authorizationStatus

        AppLogger.shared.info(
            "status_checked",
            message: "Screen Time authorization checked on scene active.",
            category: .authorization,
            metadata: ["status": "\(currentStatus)"]
        )

        if currentStatus == .approved {
            dashboardViewModel.activate()
            if lastKnownStatus != .approved && lastKnownStatus != nil {
                AppLogger.shared.info(
                    "restored",
                    message: "Screen Time authorization restored by user.",
                    category: .authorization
                )
            }
            uiState = .authorized
            lastKnownStatus = .approved
        } else {
            // Previously approved, now revoked OR non-approved state
            if lastKnownStatus == .approved {
                handleAuthorizationRevoked(newStatus: currentStatus)
            } else {
                uiState = AuthorizationStateEvaluator.evaluate(
                    status: currentStatus,
                    hasPreviouslyConfigured: storage.hasConfiguredSelection()
                )
                lastKnownStatus = currentStatus
            }
        }
    }

    private func handleAuthorizationRevoked(newStatus: AuthorizationStatus) {
        AppLogger.shared.warning(
            "revoked",
            message: "Screen Time authorization was revoked by the user in Settings.",
            category: .authorization,
            metadata: ["newStatus": "\(newStatus)"]
        )

        AppLogger.shared.warning(
            "stopped_due_to_permission",
            message: "Stopping all DeviceActivity monitoring and clearing transient runtime state due to revoked permission.",
            category: .monitoring
        )

        do {
            try MonitoringLifecycle.make(storage: storage, activity: deviceActivityService,
                                         settings: managedSettingsService).stop(all: true)
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.shared.error("revocation_cleanup_failed", message: error.localizedDescription, category: .monitoring)
        }

        let isDeniedInSettings = (newStatus == .denied)
        uiState = .permissionRevoked(isDeniedInSettings: isDeniedInSettings)
        lastKnownStatus = newStatus
    }

    func requestAuthorization() async {
        guard !isRequestingAuthorization else { return }

        isRequestingAuthorization = true
        errorMessage = nil

        defer {
            isRequestingAuthorization = false
        }

        do {
            try await authorizationService.requestAuthorization()
            let newStatus = authorizationService.authorizationStatus

            if newStatus == .approved {
                AppLogger.shared.info(
                    "restored",
                    message: "Screen Time authorization granted via in-app prompt.",
                    category: .authorization
                )
                uiState = .authorized
                lastKnownStatus = .approved
            } else {
                uiState = AuthorizationStateEvaluator.evaluate(
                    status: newStatus,
                    hasPreviouslyConfigured: storage.hasConfiguredSelection()
                )
                lastKnownStatus = newStatus
            }
        } catch {
            errorMessage = error.localizedDescription
            let currentStatus = authorizationService.authorizationStatus
            uiState = AuthorizationStateEvaluator.evaluate(
                status: currentStatus,
                hasPreviouslyConfigured: storage.hasConfiguredSelection()
            )
            lastKnownStatus = currentStatus
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else {
            return
        }
        UIApplication.shared.open(url)
    }
}
