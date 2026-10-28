import SwiftUI

/// A deadline display. Runtime reconciliation, never this clock, decides completion.
struct BLCountdownStatusView: View {
    let endsAt: Date
    var startedAt: Date? = nil
    let isDeepFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 64

    private var accent: Color { isDeepFocus ? BLColor.statusDeepFocus : BLColor.statusBreak }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = BLTimePresentation.remaining(until: endsAt, at: context.date)
            let fraction = BLTimePresentation.remainingFraction(start: startedAt, end: endsAt, at: context.date)
            VStack(spacing: BLSpacing.sm) {
                if dynamicTypeSize >= .xxLarge {
                    // Large text flows vertically without being squeezed inside a fixed dial.
                    timer(seconds: seconds, compact: true)
                } else {
                    ZStack {
                        TimelineView(.animation(minimumInterval: 1.0 / 15,
                            paused: reduceMotion || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled)) { ambient in
                            let breath = reduceMotion || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.5
                                : (sin(ambient.date.timeIntervalSinceReferenceDate * .pi / 3.25) + 1) / 2
                            Circle().fill(accent.opacity(0.04 + breath * 0.04))
                                .frame(width: 224, height: 224)
                        }
                        .accessibilityHidden(true)
                        BLStatusRing(icon: "", statusColor: accent, progress: fraction, size: 200)
                            .accessibilityHidden(true)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.72), value: fraction)
                        timer(seconds: seconds, compact: false)
                            .padding(.horizontal, BLSpacing.md)
                    }
                    .frame(maxWidth: .infinity, minHeight: 236)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func timer(seconds: Int, compact: Bool) -> some View {
        VStack(spacing: BLSpacing.xs) {
            Text(isDeepFocus ? "FOCUS TIME LEFT" : "TIME REMAINING")
                .font(BLTypography.captionBold)
                .fixedSize(horizontal: false, vertical: true)
                .tracking(1.5)
                .foregroundStyle(BLColor.textSecondary)
            if compact {
                digits(seconds: seconds, font: .system(.title2, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ViewThatFits(in: .horizontal) {
                digits(seconds: seconds, font: .system(size: displaySize, weight: .bold, design: .rounded))
                    .fixedSize()
                digits(seconds: seconds, font: .system(.largeTitle, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(isDeepFocus ? "Stay in the flow." : "Rest. Breathe. Return.")
                .font(BLTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(BLColor.brandPrimary)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, compact ? BLSpacing.md : 0)
    }

    private func digits(seconds: Int, font: Font) -> some View {
        Text(seconds == 0 ? "Finishing…" : BLTimePresentation.label(seconds: seconds))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(BLColor.textPrimary)
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: seconds)
            .accessibilityLabel(isDeepFocus ? "Focus time remaining" : "Break time remaining")
            .accessibilityValue(seconds == 0 ? "Finishing" : Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
    }
}
