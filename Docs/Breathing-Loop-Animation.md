# Breathing Loop status animation

## Implementation

Only `BreakLoop/Core/DesignSystem/Components/BLStatusRing.swift` changes in production. The prior 30 FPS TimelineView, rotating 22% orbit and periodic body evaluation are replaced by native SwiftUI ease-in-out animation. A full decorative ring breathes from 0.985 to 1.015 scale, with subtle opacity/shadow variation. The infinity symbol has restrained opacity and indigo shadow changes. Inhale/exhale take 1.8 seconds each (3.6-second full cycle). Badge text, title, description, compact Deep Focus row and all layout frames remain stable.

The existing authoritative Dashboard `.monitoring` branch supplies `isMonitoring`. This component does not infer successful monitoring from animation, use usage percentages, invent timestamps or change state. Other ring uses retain static/off/progress artwork; cooldown and focus countdown components are untouched. No shared lifecycle or persistence changes were made.

Breathing requires monitoring, a visible view, active scene, Reduce Motion off and Low Power Mode off. A change to these conditions replaces the artwork identity, removing the native repeating animation and displaying a static equivalent. Returning to active foreground creates a new breathing artwork. Low Power Mode changes arrive through a system notification rather than polling. There are no Timer, TimelineView, Task loops or rotating monitoring arcs. The remaining -90-degree rotation is a constant orientation for existing non-monitoring progress artwork.

Accessibility text never changes with the animation. The Dashboard continues to hide the decorative ring from VoiceOver and exposes its existing stable status/title instead. Dynamic Type retains the existing 100/200pt ring selection. Semantic colors and the compact Deep Focus entry remain unchanged.

## Files for this task

- `BreakLoop/Core/DesignSystem/Components/BLStatusRing.swift`
- `Tests/BreathingLoopUITests.swift` — native foreground/background, stable title-frame and real system Reduce Motion checks using screenshot pixels.
- This report.

Prior uncommitted active-Dashboard refinement files are preserved. All other 55 main-app Swift files match their task-start hashes; extension source changes were not introduced.

## Verification and artifacts

Root: `/tmp/BreakLoop-breathing-loop/`.

- Main app + DeviceActivityMonitorExtension + ShieldConfigurationExtension + ShieldActionExtension: Debug and Release builds passed. Logs: `debug-build.log`, `release-build.log`.
- Existing regression runner: 527 checks passed, including all 61 diagnostic-archive checks on this run. Log: `regressions.log`.
- Localization: 2,004 checks passed, no missing EN/TR strings. Log: `localization.log`.
- Existing native Dashboard/first-run UI tests: 9 passed (4 coexistence + 5 first-run), covering monitoring, inactive, cooldown, foreground focus, loading and failure presentation, plus EN/TR accessibility-size audits. Log: `ui-tests-system.log`.
- New motion test: 1 passed, zero failures in the final run. Results in `motion-final.log` / `motion-final.xcresult`. It compares uncompressed ring-region pixels at different times, verifies a stable title frame, sends the app to the Home screen and verifies foreground motion resumes, then enables the real simulator Settings → Accessibility → Motion → Reduce Motion switch and verifies identical ring pixels. It restores Reduce Motion to off afterward.
- Video: `Breathing-Loop-dark.mp4`, approximately 13 seconds of actual native simulator rendering; extracted frames at 2/3/4 seconds were decoded and visually inspected with AVFoundation. No generated/mock video.
- Screenshots: `screenshots/active-tr-dark.png`, `active-tr-light.png`, and inactive/cooldown/focus/loading/failure dark captures.
- `protected-result.json`: unchanged production source evidence.

The first attempt to toggle Reduce Motion hit the labelled Settings row rather than its trailing switch. The final test taps the actual control and waits for its value. Earlier failed test logs are retained; this was a harness interaction issue, not a production animation failure.

## Test boundaries and remaining risks

The isolated simulator app in `/tmp/BreakLoop-first-run/after` uses explicit fixture selection counts/runtime, skips Dashboard lifecycle activation and permission/legal routing, and adds a test-only `--breathing` flag to enable motion during recordings/new motion tests. Existing unrelated UI tests omit that flag so perpetual motion does not interfere with UI-test quiescence. The production component has no argument-based behavior and no test harness changes were shipped.

The new motion test uses the real iOS Reduce Motion preference, not an environment override. (SwiftUI exposes that environment value as read-only.) Frame comparison samples foreground pixels; background cancellation is enforced by the scene-phase gate and artwork removal, not a claim of measured background GPU utilization. This session did not profile battery usage, physically test Low Power Mode, manually navigate spoken VoiceOver or prove real-device Screen Time enforcement. The user previously requested remaining on the simulator.

No commit, push, deployment, device installation or App Group/history deletion.

Final `git diff --check`: passed. The nine existing UI tests and the final motion test passed in separate runs; the earlier combined run retained the Settings-tap failure described above.
