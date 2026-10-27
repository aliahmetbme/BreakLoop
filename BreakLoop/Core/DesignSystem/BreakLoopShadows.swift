//
//  BreakLoopShadows.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = BLSpacing.md
    var cornerRadius: CGFloat = BLRadius.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(BLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(BLColor.cardBorder, lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.03),
                radius: 8,
                x: 0,
                y: 2
            )
    }
}

extension View {
    func blCard(padding: CGFloat = BLSpacing.md, cornerRadius: CGFloat = BLRadius.card) -> some View {
        modifier(BLCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
