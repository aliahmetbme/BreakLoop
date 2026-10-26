//
//  BreakLoopDesign.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

enum BreakLoopTheme {
    static let primary = Color(red: 0.38, green: 0.32, blue: 0.88) // Modern Violet
    static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.42, green: 0.35, blue: 0.95), Color(red: 0.30, green: 0.22, blue: 0.80)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let deepFocus = Color.orange
    static let deepFocusGradient = LinearGradient(
        colors: [Color.orange, Color.red.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let success = Color.green
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let background = Color(uiColor: .systemGroupedBackground)
}

struct BreakLoopCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(BreakLoopTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func breakLoopCard() -> some View {
        modifier(BreakLoopCardModifier())
    }
}

struct BreakLoopStatusBadge: View {
    enum Status {
        case active
        case deepFocus
        case idle

        var title: String {
            switch self {
            case .active: return "BreakLoop Active"
            case .deepFocus: return "Deep Focus"
            case .idle: return "Idle"
            }
        }

        var icon: String {
            switch self {
            case .active: return "bolt.fill"
            case .deepFocus: return "flame.fill"
            case .idle: return "pause.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .active: return BreakLoopTheme.success
            case .deepFocus: return BreakLoopTheme.deepFocus
            case .idle: return .secondary
            }
        }
    }

    let status: Status

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.icon)
                .font(.caption.bold())
            Text(status.title)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(status.color)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }
}
