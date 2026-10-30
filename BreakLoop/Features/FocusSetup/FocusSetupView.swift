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

    var isModal: Bool = true

    var body: some View {
        if isModal {
            NavigationStack {
                configurationContent
                    .navigationTitle(String(localized: "Selection"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Cancel")) {
                                dismiss()
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Save")) {
                                if viewModel.saveSelection() { dismiss() }
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
                .navigationTitle(String(localized: "Selection"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save")) {
                            if viewModel.saveSelection() { dismiss() }
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
                Text("Apps & Categories")
                    .font(BLTypography.title3)
                    .foregroundStyle(BLColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
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

                // Disclaimer caption
                Text("Enforcement uses Apple Screen Time and requires authorization.")
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, BLSpacing.xs)

                Spacer(minLength: BLSpacing.xl)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(BLColor.background.ignoresSafeArea())
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
                    .fixedSize(horizontal: false, vertical: true)

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
