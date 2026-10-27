//
//  BLTertiaryButton.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLTertiaryButton: View {
    let title: String
    var icon: String? = nil
    var foregroundColor: Color = BLColor.brandPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BLSpacing.xxs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.subheadline.bold())
                }
                Text(title)
                    .font(BLTypography.secondary.weight(.semibold))
            }
            .foregroundStyle(foregroundColor)
            .padding(.vertical, BLSpacing.xs)
            .padding(.horizontal, BLSpacing.sm)
            .frame(minHeight: 44) // Meets Apple min 44pt touch target guideline
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}
