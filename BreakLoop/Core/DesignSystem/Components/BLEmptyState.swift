//
//  BLEmptyState.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: BLSpacing.md) {
            ZStack {
                Circle()
                    .fill(BLColor.surfaceSubtle)
                    .frame(width: 80, height: 80)

                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(BLColor.brandPrimary)
            }

            VStack(spacing: BLSpacing.xs) {
                Text(title)
                    .font(BLTypography.title3)
                    .foregroundStyle(BLColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(BLTypography.secondary)
                    .foregroundStyle(BLColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BLSpacing.md)
            }

            if let actionTitle = actionTitle, let action = action {
                BLSecondaryButton(title: actionTitle, isFullWidth: false, action: action)
                    .padding(.top, BLSpacing.xs)
            }
        }
        .padding(BLSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    BLEmptyState(
        icon: "apps.iphone",
        title: "No Apps Configured",
        message: "Choose which apps contribute to your shared BreakLoop budget.",
        actionTitle: "Select Apps"
    ) {}
    .background(BLColor.background)
}
