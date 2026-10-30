//
//  FocusSetupView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import SwiftUI
import FamilyControls

struct FocusSetupView: View {

    @StateObject private var viewModel = FocusSetupViewModel.makeDefault()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var isModal: Bool = true

    private let usagePresets: [BLPresetOption<Int>] = [
        BLPresetOption(label: String(localized: "10m"), value: 10),
        BLPresetOption(label: String(localized: "15m"), value: 15),
        BLPresetOption(label: String(localized: "20m"), value: 20),
        BLPresetOption(label: String(localized: "30m"), value: 30),
        BLPresetOption(label: String(localized: "45m"), value: 45),
        BLPresetOption(label: String(localized: "60m"), value: 60)
    ]

    private let breakPresets: [BLPresetOption<Int>] = [
        BLPresetOption(label: String(localized: "15m"), value: 15),
        BLPresetOption(label: String(localized: "20m"), value: 20),
        BLPresetOption(label: String(localized: "30m"), value: 30),
        BLPresetOption(label: String(localized: "45m"), value: 45),
        BLPresetOption(label: String(localized: "60m"), value: 60)
    ]

    var body: some View {
        if isModal {
            NavigationStack {
                configurationContent
                    .navigationTitle(String(localized: "Usage Cycle Setup"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Cancel")) {
                                dismiss()
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Save")) {
                                if viewModel.saveConfiguration() { dismiss() }
                            }
                            .fontWeight(.semibold)
                            .disabled(!viewModel.hasSelection)
                        }
                    }
            }
            .familyActivityPicker(
                headerText: String(localized: "Choose apps or categories"),
                footerText: String(localized: "Websites are not supported in BreakLoop v1.0. Remove any selected websites before saving."),
                isPresented: $viewModel.isPickerPresented,
                selection: $viewModel.selection
            )
            .onChange(of: viewModel.selection.breakLoopTokenCounts) { _, _ in
                viewModel.selection.logBreakLoopCounts(stage: "picker_change")
            }
        } else {
            configurationContent
                .navigationTitle(String(localized: "Manage Apps"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save")) {
                            if viewModel.saveConfiguration() { dismiss() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!viewModel.hasSelection)
                    }
                }
                .familyActivityPicker(
                    headerText: String(localized: "Choose apps or categories"),
                    footerText: String(localized: "Websites are not supported in BreakLoop v1.0. Remove any selected websites before saving."),
                    isPresented: $viewModel.isPickerPresented,
                    selection: $viewModel.selection
                )
                .onChange(of: viewModel.selection.breakLoopTokenCounts) { _, _ in
                    viewModel.selection.logBreakLoopCounts(stage: "picker_change")
                }
        }
    }

    private var configurationContent: some View {
        BLAdaptiveContainer { metrics in
            VStack(spacing: BLSpacing.lg) {
                // Visual Formula Pill
                formulaBanner
                    .padding(.top, BLSpacing.sm)

                // 1. Usage Limit Card
                usageLimitCard

                // 2. Break Duration Card
                breakDurationCard

                // 3. Managed Apps Scope Card
                managedAppsCard

                Text("Selections that include websites cannot be saved or started. Remove websites explicitly in the picker.")
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)

                if let errorMessage = viewModel.selectionIssue ?? viewModel.errorMessage {
                    Text(errorMessage)
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.destructive)
                        .multilineTextAlignment(.center)
                }

                BLPrimaryButton(title: String(localized: "Save"), icon: "checkmark.circle.fill") {
                    if viewModel.saveConfiguration() {
                        dismiss()
                    }
                }
                .disabled(!viewModel.hasSelection)

                // Disclaimer caption
                Text("Enforcement uses Apple Screen Time and requires authorization.")
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, BLSpacing.xs)

                Spacer(minLength: BLSpacing.xl)
            }
        }
        .background(BLColor.background.ignoresSafeArea())
    }

    // MARK: - Formula Summary Banner
    private var formulaBanner: some View {
        BLCard(padding: BLSpacing.md) {
            HStack(alignment: .top, spacing: BLSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BLColor.brandInteractive.opacity(0.12))
                        .frame(width: 38, height: 38)

                    Image(systemName: "infinity")
                        .font(.subheadline.bold())
                        .foregroundStyle(BLColor.brandInteractive)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "setup.formula", defaultValue: "\(viewModel.usageLimitMinutes) min use → \(viewModel.restDurationMinutes) min break"))
                        .font(BLTypography.headline)
                        .foregroundStyle(BLColor.textPrimary)

                    Text(String(localized: "setup.explanation", defaultValue: "After \(viewModel.usageLimitMinutes) minutes of combined usage, your selected apps will pause for \(viewModel.restDurationMinutes) minutes. Changes apply to next cycle."))
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.textSecondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - 1. Usage Limit Card
    private var usageLimitCard: some View {
        BLCard {
            VStack(alignment: .leading, spacing: BLSpacing.sm) {
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: BLSpacing.xxs)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                    Text("Usage Limit")
                        .font(BLTypography.headline)
                        .foregroundStyle(BLColor.textPrimary)

                    Spacer()

                    Text("Shared Usage Budget")
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.textSecondary)
                }

                BLPresetGrid(
                    options: usagePresets,
                    selected: $viewModel.usageLimitMinutes,
                    minItemWidth: 84
                )

                Text("Timer accumulates across monitored apps during an active loop window.")
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
                    .padding(.top, BLSpacing.xxs)
            }
        }
    }

    // MARK: - 2. Break Duration Card
    private var breakDurationCard: some View {
        BLCard {
            VStack(alignment: .leading, spacing: BLSpacing.sm) {
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: BLSpacing.xxs)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                    Text("Break Duration")
                        .font(BLTypography.headline)
                        .foregroundStyle(BLColor.textPrimary)

                    Spacer()

                    Text("Automatic Cooldown")
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.textSecondary)
                }

                BLPresetGrid(
                    options: breakPresets,
                    selected: $viewModel.restDurationMinutes,
                    minItemWidth: 84
                )

                Text("Your break ends at the verified cooldown deadline.")
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
                    .padding(.top, BLSpacing.xxs)
            }
        }
    }

    // MARK: - 3. Managed Apps Scope Card
    private var managedAppsCard: some View {
        Button {
            viewModel.isPickerPresented = true
        } label: {
            BLCard {
                HStack(spacing: BLSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: BLRadius.small, style: .continuous)
                            .fill(BLColor.surfaceSubtle)
                            .frame(width: 44, height: 44)

                        Image(systemName: "apps.iphone")
                            .font(.body.weight(.medium))
                            .foregroundStyle(BLColor.brandPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Apps")
                            .font(BLTypography.bodyMedium)
                            .foregroundStyle(BLColor.textPrimary)

                        if viewModel.selection.breakLoopTokenCounts.hasAny {
                            Text(String(localized: "setup.selection", defaultValue: "\(viewModel.selection.applicationTokens.count) apps, \(viewModel.selection.categoryTokens.count) categories, \(viewModel.selection.webDomainTokens.count) websites"))
                                .font(BLTypography.caption)
                                .foregroundStyle(BLColor.textSecondary)
                        } else {
                            Text("Choose your apps")
                                .font(BLTypography.caption)
                                .foregroundStyle(BLColor.brandPrimary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(BLColor.textTertiary)
                }
            }
        }
        .buttonStyle(BLPressableScaleStyle())
        .accessibilityLabel(String(localized: "Select Apps & Categories"))
    }
}

#Preview {
    FocusSetupView()
}
