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
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(BreakLoopTheme.primaryGradient)

                Text("BreakLoop")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Set your limits. Take a break. Break the loop.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "timer",
                    title: "Shared Usage Budget",
                    subtitle: "Track multiple distracting apps under one combined limit."
                )
                FeatureRow(
                    icon: "pause.circle.fill",
                    title: "Natural Rest & Cooldown",
                    subtitle: "Healthy 15-minute breaks automatically reset your cycle without shields."
                )
                FeatureRow(
                    icon: "flame.fill",
                    title: "Deep Focus Mode",
                    subtitle: "Zero-tolerance complete shielding for hours of distraction-free work."
                )
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 12) {
                if viewModel.isAuthorized {
                    Button {
                        onAuthorized?()
                    } label: {
                        Text("Continue to Dashboard")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BreakLoopTheme.primaryGradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Button {
                        Task {
                            await viewModel.requestAuthorization()
                            if viewModel.isAuthorized {
                                onAuthorized?()
                            }
                        }
                    } label: {
                        if viewModel.isRequestingAuthorization {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            Text("Enable Screen Time Access")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(BreakLoopTheme.primaryGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .disabled(viewModel.isRequestingAuthorization)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(24)
        .background(BreakLoopTheme.background.ignoresSafeArea())
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(BreakLoopTheme.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
