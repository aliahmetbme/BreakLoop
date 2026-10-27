//
//  BLPrimaryButton.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLPressableScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct BLPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isFullWidth: Bool = true
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: BLSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.headline)
                    }
                    Text(title)
                        .font(BLTypography.button)
                }
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(minHeight: 52)
            .padding(.horizontal, BLSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: BLRadius.control, style: .continuous)
                    .fill(isEnabled ? BLColor.brandInteractive : BLColor.brandInteractive.opacity(0.4))
            )
            .contentShape(RoundedRectangle(cornerRadius: BLRadius.control, style: .continuous))
        }
        .buttonStyle(BLPressableScaleStyle())
        .disabled(isLoading || !isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Light & Dark") {
    VStack(spacing: 16) {
        BLPrimaryButton(title: "Start BreakLoop", icon: "play.fill") {}
        BLPrimaryButton(title: "Loading State", isLoading: true) {}
        BLPrimaryButton(title: "Disabled State") {}
            .disabled(true)
    }
    .padding()
    .background(BLColor.background)
}
