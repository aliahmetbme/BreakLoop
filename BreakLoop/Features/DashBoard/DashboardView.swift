//
//  DashboardView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI
import FamilyControls

struct DashboardView: View {

    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject private var appearanceController: AppearanceController
    @State private var isRuleSheetPresented = false

    var body: some View {
        NavigationStack {
            BLAdaptiveContainer { metrics in
                VStack(spacing: BLSpacing.md) {
                    // Header Bar
                    dashboardHeader

                    // 1. Primary Status Surface Container
                    primaryStatusSurface

                    // 2. Rule & Target Summary Container
                    ruleSummaryCard

                    // 3. Secondary Deep Focus Entry (visible when not in Deep Focus and not in forced cooldown)
                    if viewModel.deepFocusSession?.isActive != true && !viewModel.isCooldownActive {
                        deepFocusEntryCard
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(BLTypography.caption)
                            .foregroundStyle(BLColor.destructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BLSpacing.md)
                    }

                    Spacer(minLength: BLSpacing.lg)
                }
                .padding(.top, BLSpacing.xs)
            }
            .background(BLColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $viewModel.isDeepFocusSheetPresented) {
                DeepFocusSheet(onStart: { minutes in
                    viewModel.startDeepFocus(durationMinutes: minutes)
                })
            }
            .sheet(isPresented: $isRuleSheetPresented, onDismiss: {
                viewModel.refresh()
            }) {
                FocusSetupView(isModal: true)
            }
            .onAppear {
                viewModel.refresh()
            }
        }
    }

    // MARK: - Header Bar
    private var dashboardHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: BLSpacing.xs) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("BreakLoop")
                    .font(BLTypography.title2)
                    .foregroundStyle(BLColor.textPrimary)
            }

            Spacer()

            HStack(spacing: BLSpacing.xs) {
                // Quick Mode Toggle
                Button {
                    cycleAppearance()
                } label: {
                    HStack(spacing: 4) {
                        Text("Mode")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: appearanceIcon)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(BLColor.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BLColor.surfaceSubtle)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Toggle Appearance Mode")

                // Settings Navigation Button
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.medium))
                        .foregroundStyle(BLColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(BLColor.surfaceSubtle)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(.vertical, BLSpacing.xxs)
    }

    private var appearanceIcon: String {
        switch appearanceController.appearance {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    private func cycleAppearance() {
        switch appearanceController.appearance {
        case .system: appearanceController.setAppearance(.light)
        case .light: appearanceController.setAppearance(.dark)
        case .dark: appearanceController.setAppearance(.system)
        }
    }

    // MARK: - 1. Primary Status Surface Container
    private var primaryStatusSurface: some View {
        BLCard(padding: BLSpacing.lg) {
            VStack(spacing: BLSpacing.md) {
                // Forced Break state shows badge at top
                if viewModel.isCooldownActive {
                    HStack {
                        Spacer()
                        BLStatusBadge(state: .breakActive)
                        Spacer()
                    }
                } else if let deepFocus = viewModel.deepFocusSession, deepFocus.isActive {
                    HStack {
                        Spacer()
                        BLStatusBadge(state: .deepFocus)
                        Spacer()
                    }
                }

                // Central Status Ring
                statusRingView
                    .padding(.vertical, 2)

                // Active state badge appears below the ring according to the approved design
                if viewModel.isBreakLoopActive && !viewModel.isCooldownActive && viewModel.deepFocusSession?.isActive != true {
                    BLStatusBadge(state: .active)
                }

                // Title & Subtitles
                VStack(spacing: 4) {
                    Text(statusTitle)
                        .font(BLTypography.title2)
                        .foregroundStyle(BLColor.textPrimary)
                        .multilineTextAlignment(.center)

                    if viewModel.isCooldownActive, let cooldownEnd = viewModel.cooldownEndDate {
                        Text("Apps available again at \(cooldownEnd.formatted(date: .omitted, time: .shortened))")
                            .font(BLTypography.secondarySemibold)
                            .foregroundStyle(BLColor.brandPrimary)
                            .multilineTextAlignment(.center)

                        Text("Take a short pause. Your next cycle starts automatically.")
                            .font(BLTypography.caption)
                            .foregroundStyle(BLColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    } else {
                        Text(statusSubtitle)
                            .font(BLTypography.secondary)
                            .foregroundStyle(BLColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BLSpacing.sm)
                    }
                }

                // Action Controls
                actionButtons
                    .padding(.top, BLSpacing.xs)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var statusRingView: some View {
        if let deepFocus = viewModel.deepFocusSession, deepFocus.isActive {
            BLStatusRing(
                icon: "flame.fill",
                statusColor: BLColor.statusDeepFocus,
                badgeText: "LOCKED"
            )
        } else if viewModel.isCooldownActive {
            BLStatusRing(
                icon: "leaf.fill",
                statusColor: BLColor.statusBreak,
                progress: 0.65
            )
        } else if viewModel.isBreakLoopActive {
            BLStatusRing(
                icon: "infinity",
                statusColor: BLColor.brandInteractive,
                badgeText: "ACTIVE"
            )
        } else {
            BLStatusRing(
                icon: "infinity",
                isOffState: true
            )
        }
    }

    private var statusTitle: String {
        if let deepFocus = viewModel.deepFocusSession, deepFocus.isActive {
            return "Deep Focus Active"
        } else if viewModel.isCooldownActive {
            return "Time for a break"
        } else if viewModel.isBreakLoopActive {
            return "BreakLoop Active"
        } else {
            return "BreakLoop Off"
        }
    }

    private var statusSubtitle: String {
        if let deepFocus = viewModel.deepFocusSession, deepFocus.isActive {
            return "Apps strictly shielded until \(deepFocus.endsAt.formatted(date: .omitted, time: .shortened))"
        } else if viewModel.isBreakLoopActive {
            return "Monitoring your selected apps truthful to Apple Screen Time API. Next break engages automatically at limit."
        } else {
            return "Ready when you are"
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let deepFocus = viewModel.deepFocusSession, deepFocus.isActive {
            BLSecondaryButton(title: "End Deep Focus Early", icon: "xmark.circle.fill") {
                viewModel.stopDeepFocus()
            }
        } else if viewModel.isCooldownActive {
            EmptyView()
        } else if viewModel.isBreakLoopActive {
            BLSecondaryButton(title: "Stop BreakLoop", icon: "stop.circle") {
                viewModel.stopBreakLoop()
            }
        } else {
            VStack(spacing: BLSpacing.sm) {
                BLPrimaryButton(title: "Start BreakLoop", icon: "play.fill") {
                    viewModel.startBreakLoop()
                }

                BLSecondaryButton(title: "Start Deep Focus", icon: "scope") {
                    viewModel.isDeepFocusSheetPresented = true
                }
            }
        }
    }

    // MARK: - 2. Rule & Target Summary Container
    private var ruleSummaryCard: some View {
        BLCard {
            if viewModel.isCooldownActive {
                // Forced Break Recovery Card (matching design Screen 4)
                VStack(alignment: .leading, spacing: BLSpacing.sm) {
                    HStack(alignment: .top, spacing: BLSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(BLColor.statusBreak.opacity(0.12))
                                .frame(width: 38, height: 38)

                            Image(systemName: "lock.shield.fill")
                                .font(.subheadline)
                                .foregroundStyle(BLColor.statusBreak)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(viewModel.selectedAppsCount) apps paused · \(viewModel.effectiveRestMinutes) min recovery break")
                                .font(BLTypography.headline)
                                .foregroundStyle(BLColor.textPrimary)

                            Text("Screen Time shield is active across selected apps. Step away and let your attention recover naturally.")
                                .font(BLTypography.caption)
                                .foregroundStyle(BLColor.textSecondary)
                        }
                    }

                    Divider()
                        .background(BLColor.divider)
                        .padding(.vertical, 2)

                    Button {
                        viewModel.extendCooldown(by: 15)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Need more time? Extend by 15 min", systemImage: "arrow.clockwise")
                                .font(BLTypography.secondaryMedium)
                                .foregroundStyle(BLColor.brandPrimary)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            } else if viewModel.isBreakLoopActive {
                // Active Rule Card (matching design Screen 2)
                VStack(alignment: .leading, spacing: BLSpacing.sm) {
                    HStack {
                        Label("Active Rule", systemImage: "clock.arrow.circlepath")
                            .font(BLTypography.headline)
                            .foregroundStyle(BLColor.textPrimary)

                        Spacer()

                        Text("Looping")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BLColor.brandPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(BLColor.brandPrimary.opacity(0.10))
                            .clipShape(Capsule())
                    }

                    Text("\(viewModel.effectiveLimitMinutes) min usage · \(viewModel.effectiveRestMinutes) min break")
                        .font(BLTypography.title3)
                        .foregroundStyle(BLColor.textPrimary)

                    Divider()
                        .background(BLColor.divider)

                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .font(.caption)
                            .foregroundStyle(BLColor.textSecondary)

                        Text("\(viewModel.selectedAppsCount) apps · \(viewModel.selectedCategoriesCount) categories")
                            .font(BLTypography.secondary)
                            .foregroundStyle(BLColor.textSecondary)

                        Spacer()

                        Button {
                            isRuleSheetPresented = true
                        } label: {
                            HStack(spacing: 2) {
                                Text("Edit")
                                Image(systemName: "chevron.right")
                                    .font(.caption2.bold())
                            }
                            .font(BLTypography.secondarySemibold)
                            .foregroundStyle(BLColor.brandPrimary)
                            .frame(minHeight: 44)
                        }
                    }
                }
            } else {
                // Off State Rule Card (matching design Screen 3)
                VStack(alignment: .leading, spacing: BLSpacing.sm) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(BLColor.brandInteractive)
                                .frame(width: 7, height: 7)

                            Text("Your BreakLoop")
                                .font(BLTypography.headline)
                                .foregroundStyle(BLColor.textPrimary)
                        }

                        Spacer()

                        Button {
                            isRuleSheetPresented = true
                        } label: {
                            Text("Edit")
                                .font(BLTypography.secondarySemibold)
                                .foregroundStyle(BLColor.brandPrimary)
                                .frame(minHeight: 44)
                        }
                    }

                    // Inner Interval Box
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(viewModel.effectiveLimitMinutes) min usage   \(viewModel.effectiveRestMinutes) min break")
                            .font(BLTypography.headlineBold)
                            .foregroundStyle(BLColor.textPrimary)

                        Text("Default rhythm interval")
                            .font(BLTypography.caption)
                            .foregroundStyle(BLColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BLSpacing.sm)
                    .background(BLColor.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: BLRadius.small, style: .continuous))

                    HStack(spacing: BLSpacing.xs) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(BLColor.textSecondary)

                        Text("\(viewModel.selectedAppsCount) apps · \(viewModel.selectedCategoriesCount) categories selected")
                            .font(BLTypography.caption)
                            .foregroundStyle(BLColor.textSecondary)

                        Spacer()
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(BLColor.textTertiary)

                        Text("Timer accumulates combined usage across selected apps.")
                            .font(BLTypography.caption)
                            .foregroundStyle(BLColor.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - 3. Secondary Deep Focus Entry
    private var deepFocusEntryCard: some View {
        Button {
            viewModel.isDeepFocusSheetPresented = true
        } label: {
            BLCard(padding: BLSpacing.sm) {
                HStack(spacing: BLSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: BLRadius.small, style: .continuous)
                            .fill(BLColor.surfaceSubtle)
                            .frame(width: 38, height: 38)

                        Image(systemName: "flame.fill")
                            .font(.subheadline)
                            .foregroundStyle(BLColor.brandDeep)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deep Focus")
                            .font(BLTypography.bodyMedium)
                            .foregroundStyle(BLColor.textPrimary)

                        Text("Block selected apps completely for a set period")
                            .font(BLTypography.caption)
                            .foregroundStyle(BLColor.textSecondary)
                    }

                    Spacer()

                    Text("Configure")
                        .font(BLTypography.captionBold)
                        .foregroundStyle(BLColor.brandPrimary)

                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(BLColor.textTertiary)
                }
            }
        }
        .buttonStyle(BLPressableScaleStyle())
        .accessibilityLabel("Configure Deep Focus")
    }
}

// MARK: - Deep Focus Duration Sheet
struct DeepFocusSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (Int) -> Void

    @State private var selectedDuration = 60

    let presetOptions: [BLPresetOption<Int>] = [
        BLPresetOption(label: "30m", value: 30),
        BLPresetOption(label: "1h", value: 60),
        BLPresetOption(label: "2h", value: 120),
        BLPresetOption(label: "3h", value: 180),
        BLPresetOption(label: "4h", value: 240),
        BLPresetOption(label: "5h", value: 300)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BLSpacing.lg) {
                    VStack(spacing: BLSpacing.xs) {
                        ZStack {
                            Circle()
                                .fill(BLColor.surfaceSubtle)
                                .frame(width: 60, height: 60)

                            Image(systemName: "flame.fill")
                                .font(.title2)
                                .foregroundStyle(BLColor.brandDeep)
                        }

                        Text("Deep Focus")
                            .font(BLTypography.title2)
                            .foregroundStyle(BLColor.textPrimary)

                        Text("Completely lock all selected apps for the chosen duration without pause intervals.")
                            .font(BLTypography.secondary)
                            .foregroundStyle(BLColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BLSpacing.md)
                    }
                    .padding(.top, BLSpacing.sm)

                    BLCard {
                        VStack(alignment: .leading, spacing: BLSpacing.sm) {
                            Text("Select Duration")
                                .font(BLTypography.headline)
                                .foregroundStyle(BLColor.textPrimary)

                            BLPresetGrid(
                                options: presetOptions,
                                selected: $selectedDuration,
                                minItemWidth: 84
                            )
                        }
                    }

                    BLPrimaryButton(
                        title: "Launch Deep Focus (\(selectedDuration >= 60 ? "\(selectedDuration / 60)h" : "\(selectedDuration)m"))",
                        icon: "flame.fill"
                    ) {
                        onStart(selectedDuration)
                        dismiss()
                    }

                    Spacer()
                }
                .padding(BLSpacing.md)
            }
            .background(BLColor.background.ignoresSafeArea())
            .navigationTitle("Deep Focus Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview("Dashboard") {
    DashboardView()
        .environmentObject(AppearanceController.shared)
}
