//
//  BreakLoopDesign.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

enum BreakLoopTheme {
    static let primary = BLColor.brandPrimary
    static let primaryGradient = LinearGradient(
        colors: [BLColor.brandInteractive, Color(UIColor(hex: "#3843C7"))],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let deepFocus = BLColor.brandDeep
    static let deepFocusGradient = LinearGradient(
        colors: [Color(UIColor(hex: "#262E9B")), Color(UIColor(hex: "#3843C7"))],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let success = Color.green
    static let cardBackground = BLColor.surface
    static let background = BLColor.background
}

extension View {
    func breakLoopCard() -> some View {
        blCard()
    }
}

// Backward-compatible alias for existing views
struct BreakLoopStatusBadge: View {
    enum Status {
        case active
        case deepFocus
        case idle

        var badgeState: BLStatusBadge.StatusState {
            switch self {
            case .active: return .active
            case .deepFocus: return .deepFocus
            case .idle: return .inactive
            }
        }
    }

    let status: Status

    var body: some View {
        BLStatusBadge(state: status.badgeState)
    }
}
