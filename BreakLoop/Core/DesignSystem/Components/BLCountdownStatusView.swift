import SwiftUI

/// One authoritative deadline clock. Completion remains lifecycle/reconciliation work.
struct BLCountdownStatusView: View {
    let endsAt: Date
    var startedAt: Date? = nil
    let isDeepFocus: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            BLCountdownFace(seconds: BLTimePresentation.remaining(until: endsAt, at: context.date),
                            fraction: BLTimePresentation.remainingFraction(start: startedAt, end: endsAt, at: context.date),
                            isDeepFocus: isDeepFocus)
        }
    }
}

/// Read-only layout reused by the real clock and deterministic layout fixtures.
/// Neither text length nor a tick chooses a font, diameter or layout mode.
struct BLCountdownFace: View {
    let seconds: Int
    let fraction: Double?
    let isDeepFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 48
    @ScaledMetric(relativeTo: .caption) private var captionLine: CGFloat = 18
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var compact: Bool { typeSize >= .xxLarge }
    private var accent: Color { isDeepFocus ? BLColor.statusDeepFocus : BLColor.statusBreak }
    private var regionHeight: CGFloat { compact ? captionLine * 2 : 48 }
    private var numberHeight: CGFloat { compact ? min(displaySize, 56) * 1.3 : 60 }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(CGFloat(224), max(120, proxy.size.width - 8))
            let digitWidth = compact ? proxy.size.width : diameter * 0.90
            let fontSize = min(displaySize, digitWidth / 4.8)
            Group {
                if compact {
                    VStack(spacing: BLSpacing.sm) {
                        header.frame(height: regionHeight)
                        digits(fontSize: fontSize).frame(width: digitWidth, height: numberHeight)
                        footer.frame(height: regionHeight)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ZStack {
                        BLDecorativePulse(enabled: true, period: 3.2) { frame in
                            ZStack {
                                Circle().fill(accent.opacity(0.05 + 0.10 * frame.breath))
                                    .scaleEffect(1.0 + 0.05 * frame.breath)
                                Circle().stroke(accent.opacity(0.35 * frame.rippleOpacity()), lineWidth: 2)
                                    .scaleEffect(0.98 + 0.08 * frame.ripple())
                            }
                            .frame(width: diameter, height: diameter)
                        }
                        .frame(width: diameter, height: diameter)
                        .accessibilityHidden(true)
                        BLStatusRing(icon: "", statusColor: accent, progress: fraction, size: diameter)
                            .accessibilityHidden(true)
                            .animation(reduceMotion || lowPower || scenePhase != .active ? nil : .linear(duration: 0.8), value: fraction)
                        header.frame(width: diameter * 0.74, height: regionHeight)
                            .position(x: diameter / 2, y: diameter * 0.24)
                        digits(fontSize: fontSize).frame(width: digitWidth, height: numberHeight)
                            .position(x: diameter / 2, y: diameter / 2)
                        footer.frame(width: diameter * 0.76, height: 40)
                            .position(x: diameter / 2, y: diameter * 0.76)
                    }
                    .frame(width: diameter, height: diameter)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("countdown.dial")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: compact ? regionHeight * 2 + numberHeight + BLSpacing.sm * 2 : 240)
        .onAppear { lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private var header: some View {
        Text(isDeepFocus ? String(localized: "FOCUS TIME LEFT") : String(localized: "TIME REMAINING"))
            .font(BLTypography.captionBold).tracking(1.2)
            .foregroundStyle(BLColor.textSecondary).multilineTextAlignment(.center)
            .accessibilityIdentifier("countdown.header")
    }
    private var footer: some View {
        Text(seconds <= 0 ? String(localized: "Finishing…") : (isDeepFocus ? String(localized: "Stay in the flow.") : String(localized: "Rest. Breathe. Return.")))
            .font(BLTypography.caption).foregroundStyle(BLColor.brandPrimary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("countdown.footer")
    }
    private func digits(fontSize: CGFloat) -> some View {
        Text(BLTimePresentation.label(seconds: seconds))
            .font(.system(size: fontSize, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(BLColor.textPrimary).lineLimit(1)
            .contentTransition(.identity)
            .accessibilityLabel(isDeepFocus ? String(localized: "Focus time remaining") : String(localized: "Break time remaining"))
            .accessibilityValue(seconds <= 0 ? String(localized: "accessibility.finishing", defaultValue: "Finishing") : Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
            .accessibilityIdentifier("countdown.digits")
    }
}
