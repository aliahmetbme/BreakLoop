//
//  PermissionRequiredView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct PermissionRequiredView: View {

    let isDeniedInSettings: Bool
    let isRequesting: Bool
    let errorMessage: String?
    let onAllowAccess: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        BLAdaptiveContainer { metrics in
            VStack(spacing: BLSpacing.xl) {
                Spacer(minLength: BLSpacing.lg)

                // Status Icon & Title
                VStack(spacing: BLSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(BLColor.statusBreak.opacity(0.12))
                            .frame(width: 96, height: 96)

                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(BLColor.statusBreak)
                    }

                    Text("Screen Time access needed")
                        .font(BLTypography.title)
                        .foregroundStyle(BLColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("BreakLoop needs Screen Time access to monitor and block your selected apps.")
                        .font(BLTypography.secondary)
                        .foregroundStyle(BLColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BLSpacing.md)
                }

                // Preserved Configuration Reassurance Card
                BLCard {
                    VStack(alignment: .leading, spacing: BLSpacing.sm) {
                        HStack(spacing: BLSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text("Your selected apps and categories are still saved.")
                                .font(BLTypography.footnote)
                                .foregroundStyle(BLColor.textSecondary)
                        }

                        HStack(spacing: BLSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text("Your usage budget and cooldown settings are preserved.")
                                .font(BLTypography.footnote)
                                .foregroundStyle(BLColor.textSecondary)
                        }

                        if isDeniedInSettings {
                            HStack(spacing: BLSpacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(BLColor.brandPrimary)
                                Text("Permission was disabled in iOS Settings. Tap below to re-enable it.")
                                    .font(BLTypography.footnote)
                                    .foregroundStyle(BLColor.brandPrimary)
                            }
                        }
                    }
                }

                Spacer(minLength: BLSpacing.lg)

                // Action CTAs
                VStack(spacing: BLSpacing.sm) {
                    if isDeniedInSettings {
                        BLPrimaryButton(title: String(localized: "Open iOS Settings"), icon: "gearshape.fill") {
                            onOpenSettings()
                        }
                    } else {
                        BLPrimaryButton(title: String(localized: "Allow Screen Time Access"), isLoading: isRequesting) {
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
        .background(BLColor.background.ignoresSafeArea())
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
