//
//  BLStatusRing.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLStatusRing: View {
    let icon: String
    var statusColor: Color = BLColor.brandInteractive
    var progress: Double? = nil
    var badgeText: String? = nil
    var isOffState: Bool = false
    var size: CGFloat = 100

    var isMonitoring: Bool = false
    private let strokeWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            if isOffState {
                // Calm, quiet circular container for Off state
                Circle()
                    .fill(BLColor.surfaceSubtle)
                    .frame(width: size * 0.88, height: size * 0.88)

                Image(systemName: icon)
                    .font(.system(size: size * 0.32, weight: .regular))
                    .foregroundStyle(BLColor.textTertiary)
            } else if isMonitoring {
                Circle().fill(statusColor.opacity(0.045)).frame(width: size * 0.90, height: size * 0.90)
                Circle().stroke(statusColor.opacity(0.20), lineWidth: 1.5).frame(width: size, height: size)
                Image(systemName: icon)
                    .font(.system(size: min(size * 0.32, 58), weight: .regular))
                    .foregroundStyle(statusColor)
            } else {
                Circle()
                    .stroke(statusColor.opacity(0.12), lineWidth: strokeWidth)
                    .frame(width: size, height: size)
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress ?? 0)))
                    .stroke(statusColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)

                // Center Icon and optional Badge text (e.g., "ACTIVE")
                VStack(spacing: 3) {
                    if !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: min(size * 0.32, 56), weight: .semibold))
                            .foregroundStyle(statusColor)
                    }

                    if let badgeText = badgeText {
                        Text(badgeText)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(statusColor)
                            .tracking(1.0)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badgeText ?? icon)
    }
}


#Preview {
    HStack(spacing: 24) {
        BLStatusRing(icon: "infinity", statusColor: BLColor.brandInteractive, badgeText: "ACTIVE", isMonitoring: true)
        BLStatusRing(icon: "infinity", isOffState: true)
        BLStatusRing(icon: "leaf.fill", statusColor: BLColor.statusBreak, progress: 0.65)
    }
    .padding()
    .background(BLColor.background)
}
