//
//  DashboardView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI
import FamilyControls

struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize


    @StateObject private var viewModel: DashboardViewModel

    init() { _viewModel = StateObject(wrappedValue: DashboardViewModel()) }
    init(viewModel: DashboardViewModel) { _viewModel = StateObject(wrappedValue: viewModel) }
    @EnvironmentObject private var appearanceController: AppearanceController
    @State private var isRuleSheetPresented = false

    var body: some View {
        NavigationStack {
            BLAdaptiveContainer { metrics in
                VStack(spacing: BLSpacing.md) {
                    // Header Bar
                    dashboardHeader

                    switch viewModel.experiencePresentation {
                    case .needsSelection:
                        selectionSetupCard
                        experiencePreviews
                    case .ready:
                        experienceCards
                    case .repairSelection, .selectionUnavailable:
                        selectionRepairCard
                        experiencePreviews
                    case .runtime:
                        experienceCards
                        if let issue = viewModel.selectionIssue {
                            Text(issue)
                                .font(BLTypography.caption)
                                .foregroundStyle(BLColor.destructive)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let errorMessage = viewModel.displayedError, errorMessage != viewModel.selectionIssue {
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
            .sheet(isPresented: $viewModel.isDeepFocusSheetPresented, onDismiss: {
                viewModel.dismissDeepFocusSheet()
            }) {
                DeepFocusSheet(
                    errorMessage: viewModel.deepFocusErrorMessage,
                    isLoading: viewModel.isStartingDeepFocus,
                    onStart: { minutes in
                        viewModel.startDeepFocus(durationMinutes: minutes)
                    }
                )
            }
            .sheet(isPresented: $isRuleSheetPresented, onDismiss: {
                viewModel.refresh()
            }) {
                FocusSetupView(isModal: true)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.activate() } else { viewModel.deactivate() }
            }
            .onAppear {
                if scenePhase == .active { viewModel.activate() }
            }
            .onDisappear { viewModel.deactivate() }
        }
    }

    // MARK: - Header Bar
    private var dashboardHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BLSpacing.sm) { headerBrand; headerControls }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack { headerBrand; Spacer(minLength: BLSpacing.sm); headerControls }
                    VStack(alignment: .leading, spacing: BLSpacing.sm) { headerBrand; headerControls }
                }
            }
        }
        .padding(.vertical, BLSpacing.xxs)
    }

    private var headerBrand: some View {
        HStack(spacing: BLSpacing.xs) {
            Image("AppLogo")
                .resizable().scaledToFit().frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text("BreakLoop").font(BLTypography.title2)
                .foregroundStyle(BLColor.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerControls: some View {
        HStack(spacing: BLSpacing.xs) {
                // Quick Theme Toggle
                Button {
                    cycleAppearance()
                } label: {
                    HStack(spacing: 4) {
                        Text("Theme")
                            .font(BLTypography.caption)
                        Image(systemName: appearanceIcon)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(BLColor.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BLColor.surfaceSubtle)
                    .clipShape(Capsule())
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(String(localized: "accessibility.themeButton", defaultValue: "Change appearance. Current theme: \(appearanceController.appearance.localizedTitle)."))

                // Settings Navigation Button
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.medium))
                        .foregroundStyle(BLColor.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(BLColor.surfaceSubtle)
                        .clipShape(Circle())
                }
                .accessibilityLabel(String(localized: "Settings"))
            }
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

    private var cycleState: DashboardState { viewModel.state.usageCycleState }

    private var experienceCards: some View {
        VStack(spacing: BLSpacing.md) {
            if viewModel.isDeepFocusActive {
                deepFocusCard
            } else {
                usageCycleCard
                if viewModel.canOfferDeepFocus { deepFocusEntry }
            }
        }
    }

    private var identityArtwork: some View {
        BLStatusRing(icon: "infinity", statusColor: BLColor.brandPrimary,
                     size: dynamicTypeSize.isAccessibilitySize ? 120 : 190,
                     isMonitoring: cycleState.mode == .monitoring)
            .accessibilityHidden(true)
    }

    private var usageCycleCard: some View {
        BLCard {
            VStack(spacing: BLSpacing.sm) {
                if cycleState.mode == .monitoring { BLStatusBadge(state: .active) }
                else if cycleState.mode == .cooldown { BLStatusBadge(state: .breakActive) }
                else if cycleState.mode == .inactive {
                    Text("Usage Cycle Inactive").font(BLTypography.captionBold).foregroundStyle(BLColor.textSecondary)
                }
                if cycleState.mode == .monitoring {
                    identityArtwork
                    Text("Your cycle is running.").font(BLTypography.title2)
                    Text("Selected apps are being monitored. A break begins at your shared usage limit.")
                        .font(BLTypography.secondary).foregroundStyle(BLColor.textSecondary)
                } else if cycleState.mode == .cooldown, let end = viewModel.cooldownEndDate {
                    BLCountdownStatusView(endsAt: end, isDeepFocus: false)
                    Text("Time for a break.").font(BLTypography.headlineBold)
                    Text(String(localized: "dashboard.availableAt", defaultValue: "Apps available again at \(end.formatted(date: .omitted, time: .shortened))"))
                        .font(BLTypography.caption).foregroundStyle(BLColor.textSecondary)
                    BLTertiaryButton(title: String(localized: "Extend by 15 min"), icon: "plus") {
                        viewModel.extendCooldown(by: 15)
                    }
                } else if cycleState.mode == .inactive {
                    identityArtwork
                    Text("Ready to begin?").font(BLTypography.title2)
                    Text("Use selected apps within a shared allowance, then take a break.")
                        .font(BLTypography.secondary).foregroundStyle(BLColor.textSecondary)
                } else if cycleState.mode == .loading {
                    ProgressView().accessibilityLabel(String(localized: "Updating status…"))
                    Text("Reading the latest session state").font(BLTypography.secondary)
                } else {
                    Text("Usage Cycle needs attention").font(BLTypography.headlineBold)
                    cycleRecoveryControls
                }

                if cycleState.mode == .monitoring || cycleState.mode == .inactive || cycleState.mode == .cooldown {
                    Text(String(localized: "setup.formula", defaultValue: "\(viewModel.effectiveLimitMinutes) min use → \(viewModel.effectiveRestMinutes) min break"))
                        .font(BLTypography.captionBold).foregroundStyle(BLColor.textSecondary)
                }
                if cycleState.mode == .monitoring {
                    BLTertiaryButton(title: String(localized: "Stop Usage Cycle"), icon: "stop.circle",
                                     foregroundColor: BLColor.textSecondary) { viewModel.stopBreakLoop() }
                } else if viewModel.state.mode == .inactive {
                    BLPrimaryButton(title: String(localized: "Start Usage Cycle"), icon: "play.fill") {
                        viewModel.startBreakLoop()
                    }.disabled(!viewModel.hasSelection)
                }

            }
            .foregroundStyle(BLColor.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.usageCycleCard")
    }

    private var deepFocusEntry: some View {
        Button { viewModel.presentDeepFocusSheet() } label: {
            BLCard(padding: BLSpacing.sm) {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: BLSpacing.xs))
                    : AnyLayout(HStackLayout(spacing: BLSpacing.sm))) {
                    HStack(spacing: BLSpacing.sm) {
                        Image(systemName: "scope").font(BLTypography.title3).foregroundStyle(BLColor.brandPrimary)
                        VStack(alignment: .leading, spacing: BLSpacing.xxs) {
                            Text("Deep Focus").font(BLTypography.headlineBold).foregroundStyle(BLColor.textPrimary)
                            Text("A focus session you choose.").font(BLTypography.caption).foregroundStyle(BLColor.textSecondary)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Label(String(localized: "Start"), systemImage: "chevron.right")
                        .font(BLTypography.secondarySemibold).foregroundStyle(BLColor.brandPrimary)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isStartingDeepFocus || viewModel.isDeepFocusSheetPresented)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(String(localized: "Start Deep Focus"))
        .accessibilityHint(String(localized: "Opens duration options without stopping Usage Cycle."))
        .accessibilityIdentifier("dashboard.startDeepFocus")
    }

    private var deepFocusCard: some View {
        BLCard {
            VStack(spacing: BLSpacing.md) {
                if let session = viewModel.deepFocusSession {
                    BLStatusBadge(state: .deepFocus)
                    BLCountdownStatusView(endsAt: session.endsAt, startedAt: session.startedAt, isDeepFocus: true)
                    Text("Protect your focus.").font(BLTypography.title2)
                    Text(String(localized: "dashboard.focusEnds", defaultValue: "Selected apps stay paused for this session. Focus ends at \(session.endsAt.formatted(date: .omitted, time: .shortened))"))
                        .font(BLTypography.secondary).foregroundStyle(BLColor.textSecondary)
                    if cycleState.mode == .monitoring {
                        Text("Usage Cycle continues in the background.")
                            .font(BLTypography.caption).foregroundStyle(BLColor.textSecondary)
                    } else if cycleState.mode == .cooldown, let end = viewModel.cooldownEndDate {
                        Text(String(localized: "dashboard.availableAt", defaultValue: "Apps available again at \(end.formatted(date: .omitted, time: .shortened))"))
                            .font(BLTypography.caption).foregroundStyle(BLColor.textSecondary)
                        BLTertiaryButton(title: String(localized: "Extend by 15 min"), icon: "plus") {
                            viewModel.extendCooldown(by: 15)
                        }
                    }
                    BLSecondaryButton(title: String(localized: "End Deep Focus Early"), icon: "xmark.circle.fill") {
                        viewModel.stopDeepFocus()
                    }
                }
            }
            .foregroundStyle(BLColor.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.deepFocusCard")
    }

    private var cycleRecoveryControls: some View {
        VStack(spacing: BLSpacing.xs) {
            Text(viewModel.state.recoveryDescription).font(BLTypography.caption)
                .foregroundStyle(BLColor.textSecondary)
            BLSecondaryButton(title: String(localized: "Review Selected Apps"), icon: "square.grid.2x2") {
                isRuleSheetPresented = true
            }
            BLSecondaryButton(title: String(localized: "Refresh Status"), icon: "arrow.clockwise") {
                viewModel.recoverSynchronization()
            }
            if cycleState.canStopRecordedBreakLoop {
                BLSecondaryButton(title: String(localized: "Stop Recorded Usage Cycle"), icon: "stop.circle") {
                    viewModel.stopBreakLoop()
                }
            }
            if viewModel.state.canRetryBreakLoop {
                BLPrimaryButton(title: String(localized: "Retry Usage Cycle"), icon: "arrow.clockwise.circle") {
                    viewModel.startBreakLoop()
                }.disabled(!viewModel.hasSelection)
            }
        }
    }

    // MARK: - Selection setup and equal experience entries
    private var selectionSetupCard: some View {
        BLCard {
            VStack(spacing: BLSpacing.sm) {
                identityArtwork
                Text("Ready to begin?").font(BLTypography.title2).foregroundStyle(BLColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("First, choose the apps and categories you want to take a break from.")
                    .font(BLTypography.secondary).foregroundStyle(BLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                BLPrimaryButton(title: String(localized: "Select Apps & Categories"), icon: "apps.iphone") {
                    isRuleSheetPresented = true
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectionRepairCard: some View {
        BLCard {
            VStack(alignment: .leading, spacing: BLSpacing.sm) {
                Label(viewModel.experiencePresentation == .selectionUnavailable
                    ? String(localized: "Saved selection unavailable")
                    : String(localized: "Review your selection"), systemImage: "exclamationmark.circle")
                    .font(BLTypography.headline)
                    .foregroundStyle(BLColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.selectionIssue ?? String(localized: "Review your selected apps and categories before starting."))
                    .font(BLTypography.secondary)
                    .foregroundStyle(BLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if viewModel.experiencePresentation == .selectionUnavailable {
                    BLSecondaryButton(title: String(localized: "Refresh Status"), icon: "arrow.clockwise") {
                        viewModel.refresh()
                    }
                }
                BLPrimaryButton(title: String(localized: "Review Selected Apps"), icon: "apps.iphone") {
                    isRuleSheetPresented = true
                }
            }
        }
    }

    private var experiencePreviews: some View {
        VStack(spacing: BLSpacing.sm) {
            experiencePreview(title: String(localized: "Deep Focus"),
                description: String(localized: "A focus session you choose."), icon: "sparkle")
        }
    }

    // No Button or disabled CTA: these are informational previews until setup is valid.
    private func experiencePreview(title: String, description: String, icon: String) -> some View {
        BLCard(padding: BLSpacing.sm) {
            HStack(alignment: .top, spacing: BLSpacing.sm) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BLSpacing.xxs) {
                    Text(title).font(BLTypography.headline)
                    Text(description).font(BLTypography.caption)
                    Text(viewModel.experiencePresentation == .needsSelection
                        ? String(localized: "Select apps first")
                        : String(localized: "Available after selection is verified"))
                        .font(BLTypography.captionBold)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(BLColor.textSecondary)
            .accessibilityElement(children: .combine)
        }
    }


}

// MARK: - Deep Focus Duration Sheet
struct DeepFocusSheet: View {
    @Environment(\.dismiss) private var dismiss
    var errorMessage: String? = nil
    var isLoading: Bool = false
    let onStart: (Int) -> Bool

    @State private var selectedDuration = 60

    let presetOptions: [BLPresetOption<Int>] = [
        BLPresetOption(label: String(localized: "30m"), value: 30),
        BLPresetOption(label: String(localized: "1h"), value: 60),
        BLPresetOption(label: String(localized: "2h"), value: 120),
        BLPresetOption(label: String(localized: "3h"), value: 180),
        BLPresetOption(label: String(localized: "4h"), value: 240),
        BLPresetOption(label: String(localized: "5h"), value: 300)
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

                            Image(systemName: "sparkle")
                                .font(.title2)
                                .foregroundStyle(BLColor.brandPrimary)
                        }

                        Text("Deep Focus")
                            .font(BLTypography.title2)
                            .foregroundStyle(BLColor.textPrimary)

                        Text("Pause your selected apps and categories for a focus session. You can end the session early if needed.")
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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(BLTypography.caption)
                            .foregroundStyle(BLColor.destructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BLSpacing.md)
                    }

                    BLPrimaryButton(
                        title: String(localized: "focus.launch", defaultValue: "Start Deep Focus (\(selectedDuration >= 60 ? String(localized: "duration.hours", defaultValue: "\(selectedDuration / 60)h") : String(localized: "duration.minutes", defaultValue: "\(selectedDuration)m")))"),
                        icon: "sparkle",
                        isLoading: isLoading
                    ) {
                        if onStart(selectedDuration) {
                            dismiss()
                        }
                    }

                    Spacer()
                }
                .padding(BLSpacing.md)
            }
            .background(BLColor.background.ignoresSafeArea())
            .navigationTitle(String(localized: "Deep Focus Setup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
        }
    }
}

#Preview("Dashboard") {
    DashboardView()
        .environmentObject(AppearanceController.shared)
}
