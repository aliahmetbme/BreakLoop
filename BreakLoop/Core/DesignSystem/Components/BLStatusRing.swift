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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var isVisible = false
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var shouldBreathe: Bool {
        isMonitoring && !isOffState && isVisible && !reduceMotion && scenePhase == .active && !lowPowerMode
    }

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
                BLBreathingLoopArtwork(icon: icon, statusColor: statusColor, badgeText: badgeText,
                                       size: size, animate: shouldBreathe)
                    // Replacing the artwork cancels its native repeating animation immediately.
                    .id(shouldBreathe)
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
                            .font(.system(size: min(size * 0.30, 36), weight: .semibold))
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
        .onAppear {
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            isVisible = true
        }
        .onDisappear { isVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

// Decorative liveness only. No usage progress, timestamps, timers or rotating arcs.
private struct BLBreathingLoopArtwork: View {
    let icon: String
    let statusColor: Color
    let badgeText: String?
    let size: CGFloat
    let animate: Bool
    @State private var expanded = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(statusColor.opacity(expanded ? 0.30 : 0.22), lineWidth: 3.5)
                .frame(width: size, height: size)
                .scaleEffect(animate ? (expanded ? 1.015 : 0.985) : 1)
                .shadow(color: statusColor.opacity(expanded ? 0.10 : 0.04), radius: expanded ? 9 : 5)
            VStack(spacing: 3) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: min(size * 0.30, 36), weight: .semibold))
                        .foregroundStyle(statusColor)
                        .opacity(expanded ? 1 : 0.94)
                        .shadow(color: statusColor.opacity(expanded ? 0.24 : 0.10), radius: expanded ? 7 : 3)
                }
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                        .tracking(1.0)
                }
            }
        }
        // 1.8s inhale + 1.8s exhale. Only artwork changes; layout and labels stay fixed.
        .animation(animate ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true) : nil, value: expanded)
        .onAppear { expanded = animate }
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
