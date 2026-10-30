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
                        experienceEntries
                        configurationSummary
                    case .repairSelection, .selectionUnavailable:
                        selectionRepairCard
                        experiencePreviews
                    case .runtime(let mode):
                        primaryStatusSurface
                        if mode == .monitoring || mode == .cooldown || mode == .deepFocus {
                            ruleSummaryCard
                        }
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

    // MARK: - 1. Primary Status Surface Container
    private var primaryStatusSurface: some View {
        BLCard(padding: BLSpacing.lg) {
            VStack(spacing: BLSpacing.md) {
                // Forced Break state shows badge at top
                if viewModel.isDeepFocusActive {
                    HStack {
                        Spacer()
                        BLStatusBadge(state: .deepFocus)
                        Spacer()
                    }
                } else if viewModel.isCooldownActive {
                    HStack {
                        Spacer()
                        BLStatusBadge(state: .breakActive)
                        Spacer()
                    }
                }

                if viewModel.state.mode == .monitoring {
                    BLStatusBadge(state: .active)
                }

                if viewModel.isDeepFocusActive {
                    focusCompanionNote
                }

                // Central Status Ring
                statusRingView
                    .padding(.vertical, 2)

                // Title & Subtitles
                VStack(spacing: 4) {
                    Text(statusTitle)
                        .font(BLTypography.title2)
                        .foregroundStyle(BLColor.textPrimary)
                        .multilineTextAlignment(.center)

                    if viewModel.isCooldownActive, let cooldownEnd = viewModel.cooldownEndDate {
                        Text(String(localized: "dashboard.availableAt", defaultValue: "Apps available again at \(cooldownEnd.formatted(date: .omitted, time: .shortened))"))
                            .font(BLTypography.secondarySemibold)
                            .foregroundStyle(BLColor.brandPrimary)
                            .multilineTextAlignment(.center)

                        Text("Your apps are paused. Take a moment away from the screen.")
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

                if viewModel.state.mode == .monitoring && viewModel.canOfferDeepFocus {
                    deepFocusContextAction
                }

                // Action Controls
                actionButtons
                    .padding(.top, BLSpacing.xs)
            }
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deepFocusContextAction: some View {
        Button {
            viewModel.presentDeepFocusSheet()
        } label: {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: BLSpacing.xs))
                : AnyLayout(HStackLayout(spacing: BLSpacing.sm))) {
                HStack(alignment: .center, spacing: BLSpacing.sm) {
                    Image(systemName: "scope")
                        .font(BLTypography.title3)
                        .foregroundStyle(BLColor.brandPrimary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: BLSpacing.xxs) {
                        Text("Deep Focus")
                            .font(BLTypography.secondarySemibold)
                            .foregroundStyle(BLColor.textPrimary)
                        Text("Your Usage Cycle keeps running.")
                            .font(BLTypography.caption)
                            .foregroundStyle(BLColor.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                HStack(spacing: BLSpacing.xxs) {
                    Text("Start").font(BLTypography.secondarySemibold)
                    Image(systemName: "chevron.right").font(BLTypography.captionBold)
                }
                .foregroundStyle(BLColor.brandPrimary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(BLSpacing.sm)
            .background(BLColor.brandPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: BLRadius.control))
            .overlay(RoundedRectangle(cornerRadius: BLRadius.control).strokeBorder(BLColor.cardBorder))
            .contentShape(RoundedRectangle(cornerRadius: BLRadius.control))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isStartingDeepFocus || viewModel.isDeepFocusSheetPresented)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(String(localized: "Start Deep Focus"))
        .accessibilityValue(String(localized: "Your Usage Cycle keeps running."))
        .accessibilityHint(String(localized: "Opens duration options without stopping Usage Cycle."))
        .accessibilityIdentifier("dashboard.deepFocusContextAction")
    }

    @ViewBuilder
    private var focusCompanionNote: some View {
        if viewModel.focusCompanionState != .none {
            VStack(spacing: BLSpacing.xxs) {
                Label(focusCompanionTitle, systemImage: "clock.arrow.circlepath")
                    .font(BLTypography.captionBold)
                Text(focusCompanionDescription).font(BLTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(BLColor.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    private var focusCompanionTitle: String {
        switch viewModel.focusCompanionState {
        case .usageCycle: return String(localized: "Usage Cycle remains active in the background.")
        case .cooldown: return String(localized: "Your existing break is preserved.")
        case .needsAttention: return String(localized: "Usage Cycle needs attention")
        case .none: return ""
        }
    }

    private var focusCompanionDescription: String {
        switch viewModel.focusCompanionState {
        case .usageCycle: return String(localized: "Its existing usage and rest rules still apply.")
        case .cooldown: return String(localized: "Ending Deep Focus will not end this break.")
        case .needsAttention: return String(localized: "Review its status after your focus session.")
        case .none: return ""
        }
    }

    @ViewBuilder
    private var statusRingView: some View {
        if viewModel.isDeepFocusActive, let session = viewModel.deepFocusSession {
            BLCountdownStatusView(endsAt: session.endsAt, startedAt: session.startedAt, isDeepFocus: true)
        } else if viewModel.isCooldownActive, let end = viewModel.cooldownEndDate {
            BLCountdownStatusView(endsAt: end, isDeepFocus: false)
        } else if viewModel.state.mode == .loading {
            ProgressView().controlSize(.large).frame(width: 200, height: 200)
        } else if viewModel.state.mode == .failure {
            BLStatusRing(icon: "exclamationmark.triangle", statusColor: BLColor.destructive)
        } else if viewModel.state.mode == .monitoring {
            BLStatusRing(
                icon: "infinity",
                statusColor: BLColor.brandInteractive,
                badgeText: String(localized: "ACTIVE"),
                size: dynamicTypeSize.isAccessibilitySize ? 100 : 200,
                isMonitoring: true
            )
            .accessibilityHidden(true)
        } else {
            BLStatusRing(
                icon: "infinity",
                isOffState: true
            )
        }
    }

    private var statusTitle: String {
        if viewModel.isDeepFocusActive {
            return String(localized: "Protect your focus.")
        } else if viewModel.isCooldownActive {
            return String(localized: "Time for a break.")
        } else if viewModel.state.mode == .failure {
            return String(localized: "Usage Cycle needs attention")
        } else if viewModel.state.mode == .loading {
            return String(localized: "Updating status…")
        } else if viewModel.state.mode == .monitoring {
            return String(localized: "Your cycle is running.")
        } else if !viewModel.hasSelection {
            return String(localized: "Ready to begin?")
        } else {
            return String(localized: "Usage Cycle Inactive")
        }
    }

    private var statusSubtitle: String {
        if viewModel.isDeepFocusActive, let deepFocus = viewModel.deepFocusSession {
            return String(localized: "dashboard.focusEnds", defaultValue: "Selected apps stay paused for this session. Focus ends at \(deepFocus.endsAt.formatted(date: .omitted, time: .shortened))")
        } else if viewModel.state.mode == .failure {
            return String(localized: "Reopen BreakLoop or retry after resolving the error below.")
        } else if viewModel.state.mode == .loading {
            return String(localized: "Reading the latest session state")
        } else if viewModel.state.mode == .monitoring {
            return String(localized: "Selected apps are being monitored. A break begins at your shared usage limit.")
        } else if viewModel.selectionState == .empty {
            return String(localized: "Choose the apps you want to take a break from.")
        } else if viewModel.selectionState.hasUnsupportedWebsites {
            return String(localized: "BreakLoop v1.0 supports apps and categories only. Remove selected websites to continue.")
        } else if !viewModel.hasSelection {
            return String(localized: "Review your selected apps and categories before starting.")
        } else {
            return String(localized: "Share one usage allowance across your selected apps. A break begins when it runs out.")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if viewModel.isDeepFocusActive {
            BLSecondaryButton(title: String(localized: "End Deep Focus Early"), icon: "xmark.circle.fill") {
                viewModel.stopDeepFocus()
            }
        } else if viewModel.isCooldownActive {
            EmptyView()
        } else if viewModel.canStopBreakLoop {
            if viewModel.state.mode == .monitoring {
                BLTertiaryButton(title: String(localized: "Stop Usage Cycle"), icon: "stop.circle",
                                 foregroundColor: BLColor.textSecondary) {
                    viewModel.stopBreakLoop()
                }
            } else {
                BLSecondaryButton(title: String(localized: "Stop Usage Cycle"), icon: "stop.circle") {
                    viewModel.stopBreakLoop()
                }
            }
        } else if viewModel.state.mode == .failure {
            VStack(spacing: BLSpacing.sm) {
                Text(viewModel.state.recoveryDescription)
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
                    .multilineTextAlignment(.center)
                BLSecondaryButton(title: String(localized: "Review Selected Apps"), icon: "square.grid.2x2") {
                    isRuleSheetPresented = true
                }
                BLSecondaryButton(title: String(localized: "Refresh Status"), icon: "arrow.clockwise") {
                    viewModel.recoverSynchronization()
                }
                if viewModel.state.canStopRecordedBreakLoop {
                    BLSecondaryButton(title: String(localized: "Stop Recorded Usage Cycle"), icon: "stop.circle") {
                        viewModel.stopBreakLoop()
                    }
                }
                if viewModel.state.canRetryBreakLoop {
                    BLPrimaryButton(title: String(localized: "Retry Usage Cycle"), icon: "arrow.clockwise.circle") {
                        viewModel.startBreakLoop()
                    }
                    .disabled(!viewModel.hasSelection)
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
                            Text("Your recovery break")
                                .font(BLTypography.headline)
                                .foregroundStyle(BLColor.textPrimary)

                            Text(String(localized: "dashboard.pausedApps", defaultValue: "\(viewModel.selectedAppsCount) apps paused · \(viewModel.effectiveRestMinutes) min cooldown"))
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
                            Label(String(localized: "Extend by 15 min"), systemImage: "plus")
                                .font(BLTypography.secondaryMedium)
                                .foregroundStyle(BLColor.brandPrimary)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            } else if viewModel.isDeepFocusActive, let session = viewModel.deepFocusSession {
                VStack(alignment: .leading, spacing: BLSpacing.xs) {
                    Label(String(localized: "Deep Focus session"), systemImage: "sparkle")
                        .font(BLTypography.headline).foregroundStyle(BLColor.textPrimary)
                    Text(String(localized: "dashboard.sessionPlan", defaultValue: "\(session.durationMinutes) min planned · \(viewModel.selectedAppsCount) apps selected"))
                        .font(BLTypography.caption).foregroundStyle(BLColor.textSecondary)
                }
            } else if viewModel.isBreakLoopActive {
                // Active Rule Card (matching design Screen 2)
                VStack(alignment: .leading, spacing: BLSpacing.sm) {
                    HStack {
                        Label(String(localized: "Active Rule"), systemImage: "clock.arrow.circlepath")
                            .font(BLTypography.headline)
                            .foregroundStyle(BLColor.textPrimary)

                        Spacer()

                        Text("Usage Cycle Active")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BLColor.brandPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(BLColor.brandPrimary.opacity(0.10))
                            .clipShape(Capsule())
                    }

                    Text(String(localized: "dashboard.rule", defaultValue: "\(viewModel.effectiveLimitMinutes) min usage · \(viewModel.effectiveRestMinutes) min break"))
                        .font(BLTypography.title3)
                        .foregroundStyle(BLColor.textPrimary)

                    Divider()
                        .background(BLColor.divider)

                    (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: BLSpacing.xs)) : AnyLayout(HStackLayout())) {
                        Image(systemName: "square.grid.2x2")
                            .font(.caption)
                            .foregroundStyle(BLColor.textSecondary)

                        Text(String(localized: "dashboard.selection", defaultValue: "\(viewModel.selectedAppsCount) apps · \(viewModel.selectedCategoriesCount) categories · \(viewModel.selectedWebsitesCount) websites"))
                            .font(BLTypography.secondary)
                            .foregroundStyle(BLColor.textSecondary)

                        Spacer()

                        BLTertiaryButton(title: String(localized: "Edit")) {
                            isRuleSheetPresented = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Selection setup and equal experience entries
    private var selectionSetupCard: some View {
        BLCard {
            VStack(spacing: BLSpacing.sm) {
                HStack(alignment: .center, spacing: BLSpacing.sm) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        BLStatusRing(icon: "infinity", isOffState: true, size: 64)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: BLSpacing.xxs) {
                        Text("Ready to begin?")
                            .font(BLTypography.title2)
                            .foregroundStyle(BLColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("First, choose the apps and categories you want to take a break from.")
                            .font(BLTypography.secondary)
                            .foregroundStyle(BLColor.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                BLPrimaryButton(title: String(localized: "Select Apps & Categories"), icon: "apps.iphone") {
                    isRuleSheetPresented = true
                }
            }
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
            experiencePreview(title: String(localized: "Usage Cycle"),
                description: String(localized: "Shared usage, followed by automatic breaks."), icon: "clock.arrow.circlepath")
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

    private var experienceEntries: some View {
        VStack(spacing: BLSpacing.md) {
            experienceEntry(title: String(localized: "Usage Cycle"),
                description: String(localized: "Use selected apps within a shared allowance, then take a break."),
                actionTitle: String(localized: "Start Usage Cycle"), icon: "clock.arrow.circlepath") {
                    viewModel.startBreakLoop()
                }
            experienceEntry(title: String(localized: "Deep Focus"),
                description: String(localized: "Pause selected apps for a focus session you choose."),
                actionTitle: String(localized: "Start Deep Focus"), icon: "sparkle") {
                    viewModel.presentDeepFocusSheet()
                }
        }
    }

    private func experienceEntry(title: String, description: String, actionTitle: String,
                                 icon: String, action: @escaping () -> Void) -> some View {
        BLCard {
            VStack(alignment: .leading, spacing: BLSpacing.sm) {
                Label(title, systemImage: icon)
                    .font(BLTypography.title3)
                    .foregroundStyle(BLColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(description)
                    .font(BLTypography.secondary)
                    .foregroundStyle(BLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                BLPrimaryButton(title: actionTitle, icon: "play.fill", action: action)
            }
        }
    }

    private var configurationSummary: some View {
        BLCard(padding: BLSpacing.sm) {
            VStack(alignment: .leading, spacing: BLSpacing.xs) {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: BLSpacing.xxs))
                    : AnyLayout(HStackLayout())) {
                    Text("Selected Apps")
                        .font(BLTypography.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: BLSpacing.xs) }
                    BLTertiaryButton(title: String(localized: "Edit")) {
                        isRuleSheetPresented = true
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                Text(String(localized: "dashboard.selectionSelected", defaultValue: "\(viewModel.selectedAppsCount) apps · \(viewModel.selectedCategoriesCount) categories · \(viewModel.selectedWebsitesCount) websites selected"))
                    .font(BLTypography.caption)
                Text(String(localized: "dashboard.rule", defaultValue: "\(viewModel.effectiveLimitMinutes) min usage · \(viewModel.effectiveRestMinutes) min break"))
                    .font(BLTypography.caption)
            }
            .foregroundStyle(BLColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
