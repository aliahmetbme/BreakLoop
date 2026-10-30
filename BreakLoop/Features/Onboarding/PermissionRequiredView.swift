//
//  PermissionRequiredView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct PermissionRequiredView: View {

    @Environment(\.colorScheme) private var colorScheme
    let isDeniedInSettings: Bool
    let isRequesting: Bool
    let errorMessage: String?
    let onAllowAccess: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        BLAdaptiveContainer { metrics in
            VStack(spacing: BLSpacing.lg) {
                Spacer(minLength: BLSpacing.md)

                // Trust-building Shield Emblem & Headline
                VStack(spacing: BLSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(BLColor.brandPrimary.opacity(0.08))
                            .frame(width: 96, height: 96)

                        Circle()
                            .fill(BLColor.brandPrimary.opacity(0.14))
                            .frame(width: 72, height: 72)

                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(BLColor.brandPrimary)
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: BLSpacing.xs) {
                        Text("Screen Time access needed")
                            .font(BLTypography.title)
                            .foregroundStyle(BLColor.textPrimary)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text("BreakLoop needs Apple Screen Time access to monitor usage limits and shield your selected apps.")
                            .font(BLTypography.secondary)
                            .foregroundStyle(BLColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BLSpacing.sm)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Preserved Configuration & Screen Time Explanation Card
                BLCard {
                    VStack(alignment: .leading, spacing: BLSpacing.sm) {
                        PermissionTrustRow(
                            icon: "checkmark.circle.fill",
                            iconColor: Color.green,
                            text: String(localized: "Your selected apps and categories are still saved.")
                        )

                        PermissionTrustRow(
                            icon: "checkmark.circle.fill",
                            iconColor: Color.green,
                            text: String(localized: "Your usage budget and cooldown settings are preserved.")
                        )

                        PermissionTrustRow(
                            icon: "lock.fill",
                            iconColor: BLColor.brandPrimary,
                            text: String(localized: "Monitoring and shielding run on your iPhone, and you can manage access anytime in Settings.")
                        )

                        if isDeniedInSettings {
                            Divider()
                                .background(BLColor.divider)
                                .padding(.vertical, 2)

                            HStack(alignment: .top, spacing: BLSpacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(BLColor.brandPrimary)
                                    .padding(.top, 1)
                                    .accessibilityHidden(true)
                                Text("Permission was disabled in iOS Settings. Tap below to re-enable it.")
                                    .font(BLTypography.footnote)
                                    .foregroundStyle(BLColor.brandPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Spacer(minLength: BLSpacing.md)

                // Action CTAs
                VStack(spacing: BLSpacing.sm) {
                    if isDeniedInSettings {
                        BLPrimaryButton(title: String(localized: "Open iOS Settings"), icon: "gearshape.fill") {
                            onOpenSettings()
                        }
                    } else {
                        BLPrimaryButton(
                            title: String(localized: "Allow Screen Time Access"),
                            icon: "shield.lefthalf.filled",
                            isLoading: isRequesting
                        ) {
                            onAllowAccess()
                        }
                    }

                    Text("Once re-enabled, return to BreakLoop to resume.")
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.textTertiary)
                        .multilineTextAlignment(.center)

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(BLTypography.caption)
                            .foregroundStyle(BLColor.destructive)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer(minLength: BLSpacing.sm)
            }
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                BLColor.background

                LinearGradient(
                    colors: [
                        BLColor.brandSoft.opacity(colorScheme == .dark ? 0.28 : 0.55),
                        BLColor.background.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

private struct PermissionTrustRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: BLSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(text)
                .font(BLTypography.footnote)
                .foregroundStyle(BLColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PermissionRequiredView(
        isDeniedInSettings: true,
        isRequesting: false,
        errorMessage: nil,
        onAllowAccess: {},
        onOpenSettings: {}
    )
}
