//
//  BLCard.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLCard<Content: View>: View {
    var padding: CGFloat = BLSpacing.md
    var cornerRadius: CGFloat = BLRadius.card
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BLSpacing.sm) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(BLColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(BLColor.cardBorder, lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.025),
            radius: 8,
            x: 0,
            y: 2
        )
    }
}

#Preview {
    BLCard {
        Text("Card Title")
            .font(BLTypography.headline)
        Text("Card content goes here.")
            .font(BLTypography.secondary)
            .foregroundStyle(BLColor.textSecondary)
    }
    .padding()
    .background(BLColor.background)
}
