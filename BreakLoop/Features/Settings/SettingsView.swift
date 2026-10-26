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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Usage Limit")
                                .font(.body.weight(.medium))
                            Text("Shared budget across selected apps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(viewModel.usageLimitMinutes) min")
                            .font(.headline)
                            .foregroundStyle(BreakLoopTheme.primary)
                    }

                    Stepper(
                        value: Binding(
                            get: { viewModel.usageLimitMinutes },
                            set: { viewModel.updateUsageLimit($0) }
                        ),
                        in: AppGroupStorage.CycleConfiguration.minUsageMinutes...AppGroupStorage.CycleConfiguration.maxUsageMinutes,
                        step: 5
                    ) {
                        Text("Adjust limit (5m – 60m)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Session Budget")
                } footer: {
                    Text("When this total limit is exhausted, your selected apps are shielded.")
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rest Duration")
                                .font(.body.weight(.medium))
                            Text("Cooldown or natural rest length")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(viewModel.restDurationMinutes) min")
                            .font(.headline)
                            .foregroundStyle(BreakLoopTheme.primary)
                    }

                    Stepper(
                        value: Binding(
                            get: { viewModel.restDurationMinutes },
                            set: { viewModel.updateRestDuration($0) }
                        ),
                        in: AppGroupStorage.CycleConfiguration.minRestMinutes...AppGroupStorage.CycleConfiguration.maxRestMinutes,
                        step: 5
                    ) {
                        Text("Adjust rest (15m – 60m)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Break Length")
                } footer: {
                    Text("Natural breaks of this length reset your cycle without triggering a shield.")
                }

                if let snapshot = viewModel.activeSnapshot {
                    Section("Active Cycle Snapshot") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "shield.lefthalf.filled")
                                    .foregroundStyle(BreakLoopTheme.primary)
                                Text("Cycle in progress")
                                    .font(.subheadline.bold())
                            }
                            Text("Currently enforcing \(snapshot.usageLimitMinutes)m limit and \(snapshot.restDurationMinutes)m cooldown.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Your new settings will automatically apply to the next fresh cycle.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Permissions") {
                    HStack {
                        Label("Screen Time Access", systemImage: "hourglass")
                        Spacer()
                        if viewModel.authorizationStatus == .approved {
                            Text("Approved")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        } else {
                            Text("Not Authorized")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        viewModel.resetToDefaults()
                    }
                }

                Section("About BreakLoop") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Core Engine)")
                            .foregroundStyle(.secondary)
                    }
                    Text("BreakLoop monitors your shared screen time budget and enforces intentional pauses between sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.loadSettings()
            }
        }
    }
}
