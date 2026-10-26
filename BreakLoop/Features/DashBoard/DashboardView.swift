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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Header Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if let deepFocus = viewModel.deepFocusSession, deepFocus.isActive {
                                BreakLoopStatusBadge(status: .deepFocus)
                            } else if viewModel.isBreakLoopActive {
                                BreakLoopStatusBadge(status: .active)
                            } else {
                                BreakLoopStatusBadge(status: .idle)
                            }

                            Spacer()

                            NavigationLink {
                                SettingsView()
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .background(Color(uiColor: .tertiarySystemFill))
                                    .clipShape(Circle())
                            }
                        }

                        if let deepFocus = viewModel.deepFocusSession, deepFocus.isActive {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Deep Focus Active")
                                    .font(.title2.bold())
                                Text("Apps strictly shielded until \(deepFocus.endsAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                viewModel.stopDeepFocus()
                            } label: {
                                Label("End Deep Focus Early", systemImage: "xmark.circle.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .padding(.top, 4)

                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.isBreakLoopActive ? "Monitoring Usage" : "Ready to Focus")
                                    .font(.title2.bold())
                                Text(viewModel.isBreakLoopActive ? "Selected apps will lock once you reach your limit." : "Start BreakLoop to enforce healthy pause cycles.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                if viewModel.isBreakLoopActive {
                                    Button {
                                        viewModel.stopBreakLoop()
                                    } label: {
                                        Label("Pause BreakLoop", systemImage: "pause.fill")
                                            .font(.subheadline.bold())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color(uiColor: .tertiarySystemFill))
                                            .foregroundStyle(.primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                } else {
                                    Button {
                                        viewModel.startBreakLoop()
                                    } label: {
                                        Label("Start BreakLoop", systemImage: "play.fill")
                                            .font(.subheadline.bold())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(BreakLoopTheme.primaryGradient)
                                            .foregroundStyle(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    .breakLoopCard()

                    // Quick Stats & Settings Card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Session Settings")
                            .font(.headline)

                        HStack(spacing: 12) {
                            // Usage Budget Box
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Budget", systemImage: "timer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(viewModel.effectiveLimitMinutes) min")
                                    .font(.title3.bold())
                                    .foregroundStyle(BreakLoopTheme.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Rest Box
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Cooldown", systemImage: "hourglass")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(viewModel.effectiveRestMinutes) min")
                                    .font(.title3.bold())
                                    .foregroundStyle(BreakLoopTheme.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        if viewModel.activeSnapshot != nil && viewModel.isBreakLoopActive {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.shield")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Active cycle isolated from mid-session edits.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .breakLoopCard()

                    // Selected Apps Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Managed Targets")
                                    .font(.headline)
                                Text("\(viewModel.selectedAppsCount) apps, \(viewModel.selectedCategoriesCount) categories")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            NavigationLink {
                                FocusSetupView()
                            } label: {
                                Text("Edit")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(BreakLoopTheme.primary)
                            }
                        }

                        if !viewModel.hasSelection {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("No apps selected. Tap Edit to choose.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .breakLoopCard()

                    // Deep Focus Mode Banner
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Deep Focus Mode")
                                    .font(.headline)
                                Text("Zero usage tolerance. Completely shield apps for a strict period.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "flame.fill")
                                .font(.title2)
                                .foregroundStyle(BreakLoopTheme.deepFocus)
                        }

                        Button {
                            viewModel.isDeepFocusSheetPresented = true
                        } label: {
                            Label("Launch Deep Focus", systemImage: "flame.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(BreakLoopTheme.deepFocusGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(viewModel.deepFocusSession?.isActive == true)
                    }
                    .breakLoopCard()

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(16)
            }
            .background(BreakLoopTheme.background.ignoresSafeArea())
            .navigationTitle("BreakLoop")
            .sheet(isPresented: $viewModel.isDeepFocusSheetPresented) {
                DeepFocusSheet(onStart: { minutes in
                    viewModel.startDeepFocus(durationMinutes: minutes)
                })
            }
            .onAppear {
                viewModel.refresh()
            }
        }
    }
}

struct DeepFocusSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (Int) -> Void

    let durations = [
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("3 hours", 180),
        ("4 hours", 240)
    ]

    @State private var selectedDuration: Int = 60

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "flame.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(BreakLoopTheme.deepFocus)

                    Text("Deep Focus")
                        .font(.title2.bold())

                    Text("Selected apps will be locked immediately for the chosen duration without pause cycles.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 16)

                Picker("Duration", selection: $selectedDuration) {
                    ForEach(durations, id: \.1) { name, minutes in
                        Text(name).tag(minutes)
                    }
                }
                .pickerStyle(.wheel)

                Spacer()

                Button {
                    onStart(selectedDuration)
                } label: {
                    Text("Start Deep Focus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BreakLoopTheme.deepFocusGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("Select Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
