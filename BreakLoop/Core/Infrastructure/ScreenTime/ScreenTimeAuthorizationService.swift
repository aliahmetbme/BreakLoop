//
//  ScreenTimeAuthorizationService.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//


import Foundation
import FamilyControls


protocol ScreenTimeAuthorizationServiceProtocol {
    var authorizationStatus: AuthorizationStatus { get }
    
    func requestAuthorization() async throws

}


final class ScreenTimeAuthorizationService: ScreenTimeAuthorizationServiceProtocol {
    
    private let authorizationCenter: AuthorizationCenter

    func requestAuthorization() async throws {
        try await authorizationCenter.requestAuthorization(
            for: .individual
        )
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

