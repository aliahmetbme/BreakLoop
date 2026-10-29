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

    private var authorizationRecheck: Task<Void, Never>?
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
        let configured = storage.hasConfiguredSelection()
        self.uiState = AuthorizationStateEvaluator.evaluate(status: initialStatus, hasPreviouslyConfigured: configured)
        AppLogger.shared.info("authorization_route_observed", message: "Initial authorization route sampled.",
            category: .authorization, metadata: ["phase": "initial", "sampledStatus": "\(initialStatus)",
                "hasConfiguredSelection": "\(configured)", "route": "\(uiState)",
                "observedAtEpoch": "\(Date().timeIntervalSince1970)"])
    }

    // Root and visible Dashboard share one synchronizer. Activation is idempotent, so
    // foreground recovery also works while a settings/navigation screen covers the Dashboard.
    private(set) lazy var dashboardViewModel = DashboardViewModel(
        storage: storage, deviceActivityService: deviceActivityService,
        managedSettingsService: managedSettingsService)

    func handleSceneInactive(isBackground: Bool = false) {
        authorizationRecheck?.cancel(); authorizationRecheck = nil
        AppLogger.shared.record(isBackground ? "app_backgrounded" : "app_inactive", category: .lifecycle)
        PersistentLogStore.shared.flushAsync()
        if uiState == .authorized { dashboardViewModel.deactivate() }
    }

    func handleSceneActive() {
        AppLogger.shared.withOperation("app_foreground") {
            AppLogger.shared.record("app_foregrounded", category: .lifecycle)
            let currentStatus = authorizationService.authorizationStatus
            AppLogger.shared.info("authorization_route_observed", message: "Foreground authorization status sampled.",
                category: .authorization, metadata: ["phase": "foreground", "sampledStatus": "\(currentStatus)",
                    "previousStatus": lastKnownStatus.map { "\($0)" } ?? "none", "previousRoute": "\(uiState)",
                    "hasConfiguredSelection": "\(storage.hasConfiguredSelection())",
                    "observedAtEpoch": "\(Date().timeIntervalSince1970)"])

            AppLogger.shared.info(
                "status_checked",
                message: "Screen Time authorization checked on scene active.",
                category: .authorization,
                metadata: ["status": "\(currentStatus)"]
            )

            resolveAuthorization(currentStatus)
        }
    }

    private func resolveAuthorization(_ status: AuthorizationStatus, settled: Bool = false) {
        if status == .approved {
            authorizationRecheck?.cancel(); authorizationRecheck = nil
            dashboardViewModel.activate()
            uiState = .authorized
            lastKnownStatus = .approved
        } else if AuthorizationStartupPolicy.provesRevocation(previouslyApproved: lastKnownStatus == .approved,
                                                               sample: AuthorizationStateEvaluator.sample(status)) {
            authorizationRecheck?.cancel(); authorizationRecheck = nil
            handleAuthorizationRevoked(newStatus: status)
        } else {
            if uiState == .authorized { dashboardViewModel.deactivate() }
            uiState = AuthorizationStateEvaluator.evaluate(status: status,
                hasPreviouslyConfigured: storage.hasConfiguredSelection(), settled: settled)
            // Do not convert a transient unknown/notDetermined sample into cleanup.
            if status == .denied { lastKnownStatus = status }
            if uiState == .checkingAuthorization { scheduleAuthorizationRecheck() }
        }
    }

    private func scheduleAuthorizationRecheck() {
        guard authorizationRecheck == nil else { return }
        authorizationRecheck = Task { @MainActor [weak self] in
            for (index, delay) in [250_000_000, 500_000_000, 1_000_000_000].enumerated() {
                do { try await Task.sleep(nanoseconds: UInt64(delay)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                let status = self.authorizationService.authorizationStatus
                AppLogger.shared.record("authorization_route_observed", category: .authorization,
                    metadata: ["phase": "authorization_recheck", "sampledStatus": "\(status)",
                        "hasConfiguredSelection": "\(self.storage.hasConfiguredSelection())"])
                self.resolveAuthorization(status, settled: index == 2)
                if self.uiState != .checkingAuthorization { break }
            }
            self?.authorizationRecheck = nil
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
            AppLogger.shared.failure("revocation_cleanup_failed", error: error, category: .monitoring)
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
                resolveAuthorization(newStatus)
            }
        } catch {
            errorMessage = error.localizedDescription
            let currentStatus = authorizationService.authorizationStatus
            resolveAuthorization(currentStatus)
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
