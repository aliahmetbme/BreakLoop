//
//  BLStatusBadge.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLStatusBadge: View {
    enum StatusState {
        case active
        case breakActive
        case deepFocus
        case inactive
        case permissionRequired

        var title: String {
            switch self {
            case .active: return String(localized: "Usage Cycle Active")
            case .breakActive: return String(localized: "Mindful Pause Active")
            case .deepFocus: return String(localized: "Deep Focus Active")
            case .inactive: return String(localized: "Usage Cycle Inactive")
            case .permissionRequired: return String(localized: "Permission Required")
            }
        }

        var color: Color {
            switch self {
            case .active: return BLColor.brandInteractive
            case .breakActive: return BLColor.statusBreak
            case .deepFocus: return BLColor.statusDeepFocus
            case .inactive: return BLColor.textTertiary
            case .permissionRequired: return BLColor.destructive
            }
        }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let state: StatusState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 7, height: 7)

            Text(state.title)
                .font(BLTypography.badge)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(state == .deepFocus || state == .active ? BLColor.brandPrimary : state.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(state.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? BLRadius.control : BLRadius.pill, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "accessibility.status", defaultValue: "Status: \(state.title)"))
    }
}

#Preview {
    VStack(spacing: 8) {
        BLStatusBadge(state: .active)
        BLStatusBadge(state: .breakActive)
        BLStatusBadge(state: .deepFocus)
        BLStatusBadge(state: .inactive)
        BLStatusBadge(state: .permissionRequired)
    }
    .padding()
    .background(BLColor.background)
}
