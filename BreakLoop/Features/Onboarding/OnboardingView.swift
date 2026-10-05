//
//  OnboardingView.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import SwiftUI

struct OnboardingView: View {

    @StateObject private var viewModel: OnboardingViewModel

    init(
        viewModel: OnboardingViewModel
    ) {
        _viewModel = StateObject(
            wrappedValue: viewModel
        )
    }

    var body: some View {
        VStack(spacing: 24) {

            Spacer()

            Text("BreakLoop")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(
                "Set your limits. Take a break. Break the loop."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Spacer()

            if viewModel.isAuthorized {

                Label(
                    "Screen Time Access Enabled",
                    systemImage: "checkmark.circle.fill"
                )

            } else {

                Button {
                    Task {
                        await viewModel.requestAuthorization()
                    }
                } label: {
                    if viewModel.isRequestingAuthorization {

                        ProgressView()

                    } else {

                        Text("Enable Screen Time Access")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.isRequestingAuthorization
                )
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }
}

