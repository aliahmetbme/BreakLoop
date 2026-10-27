//
//  SettingsView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI
import FamilyControls

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var appearanceController = AppearanceController.shared

    var body: some View {
        Form {
            // Section 1: BreakLoop Cycle Rules
            Section {
                // Usage Limit Row
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Usage Limit")
                                .font(BLTypography.bodyMedium)
                                .foregroundStyle(BLColor.textPrimary)
                            Text("Shared allowance across selected apps")
                                .font(BLTypography.caption)
                                .foregroundStyle(BLColor.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(viewModel.usageLimitMinutes) min")
                            .font(BLTypography.headline)
                            .foregroundStyle(BLColor.brandPrimary)
                            .monospacedDigit()
                    }

                    HStack {
                        Spacer()
                        Stepper(
                            "Usage Limit",
                            value: Binding(
                                get: { viewModel.usageLimitMinutes },
                                set: { viewModel.updateUsageLimit($0) }
                            ),
                            in: AppGroupStorage.CycleConfiguration.minUsageMinutes...AppGroupStorage.CycleConfiguration.maxUsageMinutes,
                            step: 5
                        )
                        .labelsHidden()
                    }
                }
                .padding(.vertical, 4)

                // Rest Duration Row
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rest Duration")
                                .font(BLTypography.bodyMedium)
                                .foregroundStyle(BLColor.textPrimary)
                            Text("Cooldown or natural pause length")
                                .font(BLTypography.caption)
                                .foregroundStyle(BLColor.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(viewModel.restDurationMinutes) min")
                            .font(BLTypography.headline)
                            .foregroundStyle(BLColor.brandPrimary)
                            .monospacedDigit()
                    }

                    HStack {
                        Spacer()
                        Stepper(
                            "Rest Duration",
                            value: Binding(
                                get: { viewModel.restDurationMinutes },
                                set: { viewModel.updateRestDuration($0) }
                            ),
                            in: AppGroupStorage.CycleConfiguration.minRestMinutes...AppGroupStorage.CycleConfiguration.maxRestMinutes,
                            step: 5
                        )
                        .labelsHidden()
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("BreakLoop Rules")
            } footer: {
                if let snapshot = viewModel.activeSnapshot {
                    Text("An active cycle is in progress (\(snapshot.usageLimitMinutes)m limit / \(snapshot.restDurationMinutes)m rest). Changes will take effect on your next fresh cycle.")
                } else {
                    Text("Timer runs when any monitored app is open. When depleted, a calming cooldown is enforced.")
                }
            }

            // Section 2: Apps Selection
            Section("Apps & Categories") {
                NavigationLink {
                    FocusSetupView(isModal: false)
                } label: {
                    HStack(spacing: BLSpacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(BLColor.brandInteractive.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: "apps.iphone")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(BLColor.brandInteractive)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage Monitored Apps")
                                .font(BLTypography.bodyMedium)
                                .foregroundStyle(BLColor.textPrimary)
                            Text("Configure targeted apps and categories")
                                .font(BLTypography.caption)
                                .foregroundStyle(BLColor.textSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Section 3: Screen Time Permission
            Section("Permissions") {
                HStack(spacing: BLSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(BLColor.brandInteractive.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(BLColor.brandInteractive)
                    }
                    Text("Screen Time Access")
                        .font(BLTypography.bodyMedium)
                        .foregroundStyle(BLColor.textPrimary)
                    Spacer()
                    if viewModel.authorizationStatus == .approved {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text("Approved")
                                .font(BLTypography.captionBold)
                                .foregroundStyle(Color.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(BLColor.destructive)
                            Text("Needed")
                                .font(BLTypography.captionBold)
                                .foregroundStyle(BLColor.destructive)
                        }
                    }
                }
                .padding(.vertical, 2)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString),
                       UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open iOS Settings")
                        .font(BLTypography.body)
                        .foregroundStyle(BLColor.brandPrimary)
                }
            }

            // Section 4: Appearance Selection (Direct reactive binding)
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { appearanceController.appearance },
                    set: { appearanceController.setAppearance($0) }
                )) {
                    Text("System").tag(AppAppearance.system)
                    Text("Light").tag(AppAppearance.light)
                    Text("Dark").tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 2)
            }

            // Section 5: About
            Section("About") {
                HStack {
                    Text("Version")
                        .font(BLTypography.body)
                        .foregroundStyle(BLColor.textPrimary)
                    Spacer()
                    Text("1.0.0")
                        .font(BLTypography.body)
                        .foregroundStyle(BLColor.textSecondary)
                }

                HStack {
                    Text("Engine")
                        .font(BLTypography.body)
                        .foregroundStyle(BLColor.textPrimary)
                    Spacer()
                    Text("Apple Screen Time & FamilyControls")
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BLColor.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            viewModel.loadSettings()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
