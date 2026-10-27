//
//  OnboardingView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import SwiftUI

@MainActor
struct OnboardingView: View {

    @StateObject private var viewModel: OnboardingViewModel
    var onAuthorized: (() -> Void)?

    init(onAuthorized: (() -> Void)? = nil) {
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(authorizationService: ScreenTimeAuthorizationService())
        )
        self.onAuthorized = onAuthorized
    }

    init(
        viewModel: OnboardingViewModel,
        onAuthorized: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: viewModel
        )
        self.onAuthorized = onAuthorized
    }

    var body: some View {
        BLAdaptiveContainer { metrics in
            VStack(spacing: BLSpacing.xl) {
                Spacer(minLength: BLSpacing.lg)

                // Hero Branding
                VStack(spacing: BLSpacing.md) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: BLColor.brandInteractive.opacity(0.25), radius: 12, y: 4)

                    VStack(spacing: BLSpacing.xxs) {
                        Text("BreakLoop")
                            .font(BLTypography.largeTitle)
                            .foregroundStyle(BLColor.textPrimary)

                        Text("Set your limits. Take a break. Break the loop.")
                            .font(BLTypography.secondary)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(BLColor.textSecondary)
                            .padding(.horizontal, BLSpacing.md)
                    }
                }

                // Features Container
                BLCard {
                    VStack(alignment: .leading, spacing: BLSpacing.md) {
                        FeatureRow(
                            icon: "timer",
                            title: "Shared Usage Budget",
                            subtitle: "Track multiple distracting apps under one combined limit."
                        )
                        Divider()
                            .background(BLColor.divider)
                        FeatureRow(
                            icon: "leaf.fill",
                            title: "Natural Rest & Cooldown",
                            subtitle: "Healthy 15-minute breaks automatically reset your cycle without shields."
                        )
                        Divider()
                            .background(BLColor.divider)
                        FeatureRow(
                            icon: "flame.fill",
                            title: "Deep Focus Mode",
                            subtitle: "Zero-tolerance complete shielding for hours of distraction-free work."
                        )
                    }
                }

                Spacer(minLength: BLSpacing.lg)

                // Action CTAs
                VStack(spacing: BLSpacing.sm) {
                    if viewModel.isAuthorized {
                        BLPrimaryButton(title: "Continue to Dashboard") {
                            onAuthorized?()
                        }
                    } else {
                        BLPrimaryButton(
                            title: "Enable Screen Time Access",
                            isLoading: viewModel.isRequestingAuthorization
                        ) {
                            Task {
                                await viewModel.requestAuthorization()
                                if viewModel.isAuthorized {
                                    onAuthorized?()
                                }
                            }
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
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

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: BLSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: BLRadius.small, style: .continuous)
                    .fill(BLColor.surfaceSubtle)
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(BLColor.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BLTypography.bodyMedium)
                    .foregroundStyle(BLColor.textPrimary)

                Text(subtitle)
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
