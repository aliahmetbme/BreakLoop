import SwiftUI

/// Time-driven animation frame. Content derives scale/opacity only, so layout and position never animate.
struct BLPulseFrame {
    let t: Double          // 0..<1 sawtooth over one period
    let running: Bool

    /// Smooth 0...1 "breathing" value (0 at rest).
    var breath: Double { running ? (1 - cos(2 * .pi * t)) / 2 : 0 }
    /// Outward ripple progress 0...1 for a ripple started `offset` of a period later.
    func ripple(_ offset: Double = 0) -> Double { running ? (t + offset).truncatingRemainder(dividingBy: 1) : 0 }
    /// Fade-in/fade-out envelope for a ripple at progress `p`; zero at rest.
    func rippleOpacity(_ offset: Double = 0) -> Double { running ? sin(.pi * ripple(offset)) : 0 }
}

/// Local transform/opacity phase only. It never reads storage or drives runtime state.
struct BLDecorativePulse<Content: View>: View {
    let enabled: Bool
    var period: Double = 2.4
    @ViewBuilder let content: (BLPulseFrame) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var runs: Bool { enabled && visible && scenePhase == .active && !reduceMotion && !lowPower }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !runs)) { context in
            let t = (context.date.timeIntervalSinceReferenceDate / period).truncatingRemainder(dividingBy: 1)
            content(BLPulseFrame(t: t, running: runs))
        }
        .onAppear { lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled; visible = true }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
