//
//  BLPresetGrid.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLPresetOption<T: Hashable>: Identifiable {
    let id: T
    let label: String
    let value: T

    init(label: String, value: T) {
        self.id = value
        self.label = label
        self.value = value
    }
}

struct BLPresetGrid<T: Hashable>: View {
    let options: [BLPresetOption<T>]
    @Binding var selected: T
    var minItemWidth: CGFloat = 84

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: minItemWidth), spacing: BLSpacing.sm)
            ],
            spacing: BLSpacing.sm
        ) {
            ForEach(options) { option in
                let isSelected = (selected == option.value)
                Button {
                    selected = option.value
                } label: {
                    Text(option.label)
                        .font(BLTypography.bodyMedium)
                        .foregroundStyle(isSelected ? Color.white : BLColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46) // Accessible touch target
                        .padding(.horizontal, BLSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: BLRadius.small, style: .continuous)
                                .fill(isSelected ? BLColor.brandInteractive : BLColor.surfaceSubtle)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BLRadius.small, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.clear : BLColor.divider,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(BLPressableScaleStyle())
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var selected = 20
        let options = [
            BLPresetOption(label: "10m", value: 10),
            BLPresetOption(label: "15m", value: 15),
            BLPresetOption(label: "20m", value: 20),
            BLPresetOption(label: "30m", value: 30),
            BLPresetOption(label: "45m", value: 45),
            BLPresetOption(label: "60m", value: 60)
        ]
        var body: some View {
            BLPresetGrid(options: options, selected: $selected)
                .padding()
                .background(BLColor.background)
        }
    }
    return PreviewWrapper()
}
