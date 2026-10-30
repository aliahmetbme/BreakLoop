import SwiftUI

/// A compact read-only companion, never a second owner or a persisted presentation flag.
struct BackgroundCycleIndicator: View {
    let state: DashboardFocusCompanionState
    private var title: String {
        switch state {
        case .usageCycle: return String(localized: "Usage Cycle active in background.")
        case .cooldown: return String(localized: "Usage Cycle break active.")
        case .needsAttention: return String(localized: "Usage Cycle needs attention")
        case .none: return ""
        }
    }
    private var color: Color {
        state == .usageCycle ? BLColor.statusActive : (state == .cooldown ? BLColor.statusBreak : BLColor.destructive)
    }
    var body: some View {
        if state != .none {
            HStack(spacing: BLSpacing.xs) {
                Image(systemName: state == .cooldown ? "pause.circle" : (state == .needsAttention ? "exclamationmark.circle" : "infinity"))
                    .foregroundStyle(BLColor.brandPrimary).accessibilityHidden(true)
                BLDecorativePulse(enabled: state == .usageCycle, period: 3.0) { frame in
                    Circle().fill(color).frame(width: 6, height: 6)
                        .shadow(color: color.opacity(0.04 + 0.14 * frame.breath), radius: 3)
                        .scaleEffect(0.94 + 0.14 * frame.breath).opacity(0.72 + 0.28 * frame.breath)
                }
                .frame(width: 12, height: 16).accessibilityHidden(true)
                Text(title).font(BLTypography.caption).foregroundStyle(BLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BLSpacing.xs)
            .frame(maxWidth: .infinity)
            .background(BLColor.surfaceSubtle.opacity(0.6), in: RoundedRectangle(cornerRadius: BLRadius.control))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityIdentifier("dashboard.backgroundCycle")
        }
    }
}
