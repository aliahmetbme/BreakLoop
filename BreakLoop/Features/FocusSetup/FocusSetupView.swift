//
//  FocusSetupView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import SwiftUI
import FamilyControls

struct FocusSetupView: View {

    @StateObject private var viewModel = FocusSetupViewModel()

    var body: some View {
        VStack(spacing: 24) {

            Text("Choose Apps")
                .font(.largeTitle.bold())

            Text(
                "Select the apps or categories you want BreakLoop to manage."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Button("Select Apps & Categories") {
                viewModel.isPickerPresented = true
            }
            .buttonStyle(.borderedProminent)

            if viewModel.hasSelection {
                VStack(spacing: 8) {
                    Text("Selection saved")
                        .fontWeight(.semibold)

                    Text(
                        "\(viewModel.selection.applicationTokens.count) apps"
                    )

                    Text(
                        "\(viewModel.selection.categoryTokens.count) categories"
                    )
                }
            }

            Spacer()
        }
        .padding(24)
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
