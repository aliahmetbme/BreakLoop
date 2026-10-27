//
//  BLSecondaryButton.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLSecondaryButton: View {
    let title: String
    var icon: String? = nil
    var isFullWidth: Bool = true
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: BLSpacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.subheadline.bold())
                }
                Text(title)
                    .font(BLTypography.button)
            }
            .foregroundStyle(isEnabled ? BLColor.secondaryButtonForeground : BLColor.secondaryButtonForeground.opacity(0.4))
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(minHeight: 48)
            .padding(.horizontal, BLSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BLRadius.control, style: .continuous)
                    .fill(isEnabled ? BLColor.secondaryButtonBackground : BLColor.secondaryButtonBackground.opacity(0.5))
            )
            .contentShape(RoundedRectangle(cornerRadius: BLRadius.control, style: .continuous))
        }
        .buttonStyle(BLPressableScaleStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack(spacing: 16) {
        BLSecondaryButton(title: "Stop BreakLoop", icon: "stop.circle") {}
        BLSecondaryButton(title: "Start Deep Focus", icon: "flame.fill") {}
    }
    .padding()
    .background(BLColor.background)
}
