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
                BLDecorativePulse(enabled: isMonitoring, period: 2.4) { frame in
                    // Fixed frame: everything below only changes scale/opacity and stays inside `size`.
                    ZStack {
                        // Two outward ripples (radar ping) fading out as they reach the frame edge
                        ForEach([0.0, 0.5], id: \.self) { offset in
                            Circle()
                                .stroke(statusColor.opacity(0.55 * frame.rippleOpacity(offset)), lineWidth: 2.5)
                                .scaleEffect(0.80 + 0.20 * frame.ripple(offset))
                        }
                        // Breathing core: glow, ring and icon grow and shrink together
                        Group {
                            Circle().fill(RadialGradient(colors: [statusColor.opacity(0.10 + 0.20 * frame.breath), .clear],
                                                          center: .center, startRadius: 0, endRadius: size * 0.46))
                            Circle().stroke(statusColor.opacity(0.30 + 0.35 * frame.breath), lineWidth: 2.5)
                            Image(systemName: icon)
                                .font(.system(size: min(size * 0.32, 58), weight: .semibold))
                                .foregroundStyle(statusColor)
                                .scaleEffect(0.94 + 0.14 * frame.breath)
                                .shadow(color: statusColor.opacity(0.10 + 0.40 * frame.breath), radius: 4 + 8 * frame.breath)
                        }
                        .frame(width: size * 0.80, height: size * 0.80)
                        .scaleEffect(0.95 + 0.07 * frame.breath)
                    }
                    .frame(width: size, height: size)
                }
                .frame(width: size, height: size)
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
