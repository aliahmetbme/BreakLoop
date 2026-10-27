//
//  BreakLoopResponsive.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLLayoutMetrics: Equatable {
    let availableWidth: CGFloat
    let horizontalPadding: CGFloat
    let contentMaxWidth: CGFloat
    let prefersStackedMetrics: Bool
    let isCompact: Bool
    let isLarge: Bool

    init(availableWidth: CGFloat) {
        self.availableWidth = availableWidth

        if availableWidth < 360 {
            self.horizontalPadding = 16
            self.contentMaxWidth = availableWidth
            self.prefersStackedMetrics = true
            self.isCompact = true
            self.isLarge = false
        } else if availableWidth <= 430 {
            self.horizontalPadding = 20
            self.contentMaxWidth = availableWidth
            self.prefersStackedMetrics = false
            self.isCompact = false
            self.isLarge = false
        } else {
            self.horizontalPadding = 24
            self.contentMaxWidth = 600
            self.prefersStackedMetrics = false
            self.isCompact = false
            self.isLarge = true
        }
    }
}

struct BLAdaptiveContainer<Content: View>: View {
    @ViewBuilder let content: (BLLayoutMetrics) -> Content

    var body: some View {
        GeometryReader { proxy in
            let metrics = BLLayoutMetrics(availableWidth: proxy.size.width)
            ScrollView {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        content(metrics)
                    }
                    .frame(maxWidth: metrics.contentMaxWidth)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, metrics.horizontalPadding)
            }
        }
    }
}
