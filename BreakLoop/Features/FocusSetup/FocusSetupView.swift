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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 48))
                        .foregroundStyle(BreakLoopTheme.primary)

                    Text("Choose Apps")
                        .font(.title2.bold())

                    Text("Select the apps or categories to be monitored under your shared BreakLoop budget.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Current Selection")
                            .font(.headline)
                        Spacer()
                        if viewModel.hasSelection {
                            Text("Saved")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }
                    }

                    if viewModel.hasSelection {
                        VStack(spacing: 8) {
                            HStack {
                                Label("Applications", systemImage: "app.badge")
                                Spacer()
                                Text("\(viewModel.selection.applicationTokens.count) selected")
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack {
                                Label("Categories", systemImage: "folder")
                                Spacer()
                                Text("\(viewModel.selection.categoryTokens.count) selected")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    } else {
                        Text("No apps or categories selected yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .breakLoopCard()

                Button {
                    viewModel.isPickerPresented = true
                } label: {
                    Label(viewModel.hasSelection ? "Change Selection" : "Select Apps & Categories", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BreakLoopTheme.primaryGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(16)
        }
        .background(BreakLoopTheme.background.ignoresSafeArea())
        .navigationTitle("Manage Apps")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(
            isPresented: $viewModel.isPickerPresented,
            selection: $viewModel.selection
        )
        .onChange(of: viewModel.isPickerPresented) {
            if !viewModel.isPickerPresented {
                viewModel.saveSelection()
            }
        }
    }
}
