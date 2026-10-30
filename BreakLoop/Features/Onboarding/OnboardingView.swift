//
//  OnboardingView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import SwiftUI

@MainActor
struct OnboardingView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: OnboardingViewModel
    @ObservedObject private var terms: TermsAcceptanceModel
    @State private var keepsFooterInline: Bool
    var onAuthorized: (() -> Void)?

    init(terms: TermsAcceptanceModel? = nil, onAuthorized: (() -> Void)? = nil) {
        let termsModel = terms ?? TermsAcceptanceModel()
        self.terms = termsModel
        _keepsFooterInline = State(initialValue: !termsModel.hasAcceptedCurrentTerms)
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(authorizationService: ScreenTimeAuthorizationService())
        )
        self.onAuthorized = onAuthorized
    }

    init(
        viewModel: OnboardingViewModel,
        terms: TermsAcceptanceModel? = nil,
        onAuthorized: (() -> Void)? = nil
    ) {
        let termsModel = terms ?? TermsAcceptanceModel()
        self.terms = termsModel
        _keepsFooterInline = State(initialValue: !termsModel.hasAcceptedCurrentTerms)
        _viewModel = StateObject(
            wrappedValue: viewModel
        )
        self.onAuthorized = onAuthorized
    }

    var body: some View {
        BLAdaptiveContainer { metrics in
            VStack(spacing: metrics.isCompact ? BLSpacing.sm : BLSpacing.md) {
                // 1. Compact Hero Section
                heroSection(metrics: metrics)
                    .padding(.top, BLSpacing.xs)

                // 2. Outcome-Led Feature Cards
                featuresSection

                // Scrolls with the cards; never enlarges the fixed permission bar.
                VStack(alignment: .leading, spacing: BLSpacing.xxs) {
                    LegalLinksView(compact: true, documents: [.privacy, .terms])
                    Text("Screen Time permission is separate from legal terms, privacy information and any personal-data consent.")
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Inline footer only for Accessibility Dynamic Type sizes so large text scrolls freely
                if dynamicTypeSize.isAccessibilitySize || keepsFooterInline {
                    permissionFooterContent
                        .padding(.top, BLSpacing.xs)
                        .padding(.bottom, BLSpacing.md)
                } else {
                    Spacer(minLength: BLSpacing.xs)
                }
            }
            .padding(.bottom, BLSpacing.xs)
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                BLColor.background

                // Subtle ambient top glow for Quiet Horizon depth
                LinearGradient(
                    colors: [
                        BLColor.brandSoft.opacity(colorScheme == .dark ? 0.30 : 0.60),
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize && !keepsFooterInline {
                stickyPermissionBar
            }
        }
    }

    // MARK: - 1. Hero Section
    private func heroSection(metrics: BLLayoutMetrics) -> some View {
        VStack(spacing: BLSpacing.sm) {
            // Brand Lockup Capsule
            HStack(spacing: BLSpacing.xs) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)

                Text("BreakLoop")
                    .font(BLTypography.secondarySemibold)
                    .foregroundStyle(BLColor.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(BLColor.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(BLColor.cardBorder, lineWidth: 1)
            )
            .shadow(
                color: BLColor.brandInteractive.opacity(colorScheme == .dark ? 0.16 : 0.08),
                radius: 8,
                y: 2
            )
            .accessibilityElement(children: .combine)

            // Approved Hero Headline & Short Benefit-Oriented Explanatory Sentence
            VStack(spacing: BLSpacing.xs) {
                Text("Focus when you choose. Pause when you need.")
                    .font(metrics.isCompact ? BLTypography.title3 : BLTypography.title)
                    .foregroundStyle(BLColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Set shared usage limits and take intentional breaks from distracting apps.")
                    .font(BLTypography.secondary)
                    .foregroundStyle(BLColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BLSpacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 2. Feature Cards
    private var featuresSection: some View {
        VStack(spacing: BLSpacing.sm) {
            FeatureStoryCard(
                icon: "timer",
                accentColor: BLColor.brandPrimary,
                outcomeTag: String(localized: "One shared allowance"),
                title: String(localized: "Shared Usage Budget"),
                subtitle: String(localized: "A repeating cycle of shared app usage and rest, rather than a daily limit.")
            )

            FeatureStoryCard(
                icon: "leaf.fill",
                accentColor: BLColor.statusBreak,
                outcomeTag: String(localized: "Space to reset"),
                title: String(localized: "Cooldown & Natural Rest"),
                subtitle: String(localized: "Apps pause at your limit. Estimated time away may allow a new cycle to begin.")
            )

            FeatureStoryCard(
                icon: "sparkle",
                accentColor: BLColor.statusDeepFocus,
                outcomeTag: String(localized: "Room to focus"),
                title: String(localized: "Deep Focus"),
                subtitle: String(localized: "Pause selected apps right away for a chosen duration.")
            )
        }
    }

    // MARK: - 3. Safe-Area Sticky Permission Bar & Footer Content
    private var stickyPermissionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(BLColor.cardBorder.opacity(0.45))

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                permissionFooterContent
                    .frame(maxWidth: 600)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, BLSpacing.sm)
            .padding(.bottom, BLSpacing.xs)
        }
        .background(
            BLColor.background
                .opacity(colorScheme == .dark ? 0.94 : 0.96)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var permissionFooterContent: some View {
        VStack(spacing: BLSpacing.xs) {
            HStack(alignment: .center, spacing: BLSpacing.xs) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(BLColor.brandPrimary)
                    .accessibilityHidden(true)

                Text("Uses Apple Screen Time on your iPhone to monitor usage limits and shield selected apps.")
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, BLSpacing.xxs)
            .accessibilityElement(children: .combine)

            termsAcceptanceControl

            if viewModel.isAuthorized {
                BLPrimaryButton(
                    title: String(localized: "Continue to Dashboard"),
                    icon: "arrow.right.circle.fill"
                ) {
                    guard terms.acceptIfNeeded() else { return }
                    onAuthorized?()
                }
                .disabled(!terms.canContinue)
            } else {
                BLPrimaryButton(
                    title: String(localized: "Enable Screen Time Access"),
                    icon: "shield.lefthalf.filled",
                    isLoading: viewModel.isRequestingAuthorization
                ) {
                    guard terms.acceptIfNeeded() else { return }
                    Task {
                        await viewModel.requestAuthorization()
                        if viewModel.isAuthorized {
                            onAuthorized?()
                        }
                    }
                }
                .disabled(!terms.canContinue)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BLSpacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var termsAcceptanceControl: some View {
        VStack(alignment: .leading, spacing: BLSpacing.xxs) {
            if !terms.hasAcceptedCurrentTerms {
                Toggle(isOn: $terms.isChecked) {
                    Text("I agree to the Terms of Use.")
                        .font(BLTypography.footnote)
                        .foregroundStyle(BLColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(TermsCheckboxStyle())
                .disabled(terms.currentVersion == nil || viewModel.isRequestingAuthorization)
            }
            if terms.isDevelopmentPreview {
                Text("Development preview: this acceptance is for testing only. Final documents are pending.")
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
            } else if !terms.publicationsReady {
                Text("Continue will be available once the final legal documents are published.")
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
            }
            if terms.saveFailed {
                Text("Your acceptance could not be saved. Please try again.")
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.destructive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct TermsCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: BLSpacing.sm) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? BLColor.brandPrimary : BLColor.textSecondary)
                    .accessibilityHidden(true)
                configuration.label
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "I agree to the Terms of Use."))
        .accessibilityValue(configuration.isOn ? String(localized: "Checked") : String(localized: "Unchecked"))
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

private struct FeatureStoryCard: View {
    let icon: String
    let accentColor: Color
    let outcomeTag: String
    let title: String
    let subtitle: String

    var body: some View {
        BLCard(padding: BLSpacing.md) {
            HStack(alignment: .top, spacing: BLSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: BLRadius.small, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(outcomeTag)
                        .font(BLTypography.captionBold)
                        .foregroundStyle(accentColor)

                    Text(title)
                        .font(BLTypography.headline)
                        .foregroundStyle(BLColor.textPrimary)

                    Text(subtitle)
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    OnboardingView()
}
