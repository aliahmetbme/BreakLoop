//
//  BLMetricTile.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLMetricTile: View {
    let title: String
    let value: String
    var icon: String? = nil
    var tint: Color = BLColor.brandInteractive

    var body: some View {
        VStack(alignment: .leading, spacing: BLSpacing.xxs) {
            HStack(spacing: BLSpacing.xxs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(BLColor.textSecondary)
                }
                Text(title)
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
            }

            Text(value)
                .font(BLTypography.title3)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BLSpacing.sm)
        .background(BLColor.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: BLRadius.small, style: .continuous))
    }
}

#Preview {
    HStack {
        BLMetricTile(title: "Usage Budget", value: "20 min", icon: "timer")
        BLMetricTile(title: "Cooldown", value: "15 min", icon: "hourglass")
    }
    .padding()
    .background(BLColor.background)
}
