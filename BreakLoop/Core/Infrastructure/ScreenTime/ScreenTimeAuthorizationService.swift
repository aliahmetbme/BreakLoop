//
//  ScreenTimeAuthorizationService.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//


import Foundation
import FamilyControls


enum AuthorizationUIState: Equatable {
    case authorized
    case firstTimeOnboarding
    case permissionRevoked(isDeniedInSettings: Bool)
}

struct AuthorizationStateEvaluator {
    static func evaluate(
        status: AuthorizationStatus,
        hasPreviouslyConfigured: Bool
    ) -> AuthorizationUIState {
        switch status {
        case .approved:
            return .authorized
        case .denied:
            return .permissionRevoked(isDeniedInSettings: true)
        case .notDetermined:
            if hasPreviouslyConfigured {
                return .permissionRevoked(isDeniedInSettings: false)
            } else {
                return .firstTimeOnboarding
            }
        @unknown default:
            return .permissionRevoked(isDeniedInSettings: true)
        }
    }
}

protocol ScreenTimeAuthorizationServiceProtocol {
    var authorizationStatus: AuthorizationStatus { get }
    
    func requestAuthorization() async throws
}


final class ScreenTimeAuthorizationService: ScreenTimeAuthorizationServiceProtocol {
    
    private let authorizationCenter: AuthorizationCenter

    func requestAuthorization() async throws {
        let operationID = UUID().uuidString
        AppLogger.shared.record("authorization_request_attempted", category: .authorization, outcome: "attempted", metadata: ["operationId": operationID])
        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            AppLogger.shared.record("authorization_request_completed", category: .authorization, outcome: "succeeded",
                metadata: ["operationId": operationID, "status": "\(authorizationCenter.authorizationStatus)"])
        } catch {
            AppLogger.shared.failure("authorization_request_failed", error: error, category: .authorization,
                metadata: ["operationId": operationID, "status": "\(authorizationCenter.authorizationStatus)"])
            throw error
        }
    }
    
    init (
        authorizationCenter: AuthorizationCenter = .shared
    ) {
        self.authorizationCenter = authorizationCenter
    }
    
    var authorizationStatus: AuthorizationStatus {
            authorizationCenter.authorizationStatus
        }

    
}

