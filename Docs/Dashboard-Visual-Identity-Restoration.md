# Dashboard visual identity restoration

## Presentation correction

The infinity-centered hero is restored without reverting commits or replacing the working tree. Only Dashboard presentation, static artwork, one EN/TR line and corresponding UI tests change in this task. The preceding Settings separation, selection-only editor, native Privacy/Terms scope and Terms receipt behavior remain intact.

- Empty selection: large branded infinity, Ready to begin, familiar selection guidance and Select Apps & Categories. Below is one compact noninteractive Deep Focus preview.
- Configured/inactive: one infinity-centered cycle hero, actual configured usage/rest formula and Start Usage Cycle. A separate compact tappable focus row provides Start, without another large blue CTA.
- Monitoring: active badge, static infinity identity, stable status text, one effective snapshot-based formula and quiet Stop. Focus remains available in its own compact row below the hero.
- Focus active, alone or overlapping: exactly one focus hero, original real countdown/deadline, status message and End Early. The cycle hero is not rendered. A valid normal cycle gets one subtle background-continuation line. If a cooldown owns restrictions instead, its real deadline and quiet extension action remain available inside the focus hero; no second large card or second live timer is introduced.
- Cooldown: original real countdown/deadline and +15-minute extension remain. Focus start remains unavailable.
- Loading/failure/selection repair: authoritative synchronization/attention guards and existing review/refresh/recorded-stop/retry controls are preserved. No unverified owner is advertised as active.

There is no separate Active Rule card, repeated app count or pair of configuration links at the hero footer. Configuration and selection remain accessible through the existing Settings header button; first-use and recovery selection actions remain available.

## Artwork

The experimental orbit ellipses, breathing state, repeating animation, visibility/power notification machinery and shadow pulse are removed from BLStatusRing. The monitoring identity is a static full outline with a restrained tinted inner surface and a large infinity symbol. Hero size is 190pt normally and 120pt at accessibility sizes. Non-monitoring identity retains a quiet outline. No usage percentage or fake progress is supplied by the Dashboard.

The restored identity has no Timer, TimelineView, repeatForever or animation subscription. It stays static in normal foreground, background/return, Reduce Motion and Low Power Mode. Genuine countdowns retain their existing timestamp-driven behavior and accessibility handling; no countdown/enforcement source changed.

## Files changed by this task only

- `BreakLoop/Features/DashBoard/DashboardView.swift`
- `BreakLoop/Core/DesignSystem/Components/BLStatusRing.swift`
- `BreakLoop/Localizable.xcstrings` — “Usage Cycle continues in the background.” / “Kullanım Döngüsü arka planda devam ediyor.”
- `Tests/DeepFocusCoexistenceUITests.swift` — hero/compact entry ordering and exclusive focus priority, including independently owned cooldown.
- `Tests/BreathingLoopUITests.swift` — legacy test file now checks that the identity remains static, including foreground/background and real system Reduce Motion.
- This report.

Task-start hashes verify all other production Swift files are unchanged, including state projection/synchronization, ViewModels, lifecycle, checkpoints/Natural Rest, persistence, selection setup, Settings, legal acceptance and all extensions. Existing dirty files from the previous task are preserved; the task-only patch is separate from the cumulative Git diff.

## Actual results

- 13 native UI tests passed together, zero failures. Includes first-use/ready, monitoring hero, compact focus sheet/cancel, focus-only overlap, cooldown ownership controls, loading/failure/recovery, Settings legal scope, selection editor and EN/TR accessibility-size audits.
- The static-identity test compares ring-region pixels over time, checks stable title layout, backgrounds/reactivates the app, and repeats with the actual simulator Reduce Motion switch enabled. Both normal and Reduce Motion render static artwork.
- Full regressions: final isolated run passed 527 checks. The first run failed the existing concurrent diagnostic-archive worker test; this remains an intermittent pre-existing test concern, not a logger fix. Both logs are retained.
- Deep Focus Dashboard: 29 passed.
- Ownership/selection isolation: 21 passed, including exact snapshot/checkpoint retention, focus/cycle termination and independent cooldown ownership.
- Settings configuration save/failure: 10 passed.
- Legal publication/link handling: 28 passed.
- Terms acceptance: 26 Debug + 26 Release passed, including preserved receipt version/timestamp.
- EN/TR localization: 2,047 checks passed, 326 catalog entries including bundle-specific duplicates; no missing translations.
- Main app and all three extensions: Debug and Release builds passed.
- `git diff --check`: passed.

The inherited selection-editor audit exception remains limited to contrast of the disabled native Save/Kaydet control; no enabled content or clipping checks are excluded. The test does not enable an invalid selection to satisfy an audit.

## Screenshots and logs

Artifacts: `/tmp/BreakLoop-identity/`.

- Before: `before-screenshots/dashboard-active-valid-tr-dark-430-default-top.png` and the preceding two-large-card overlap capture.
- After active: `screenshots/active-valid-tr-dark-430-default-top.png`.
- First use: `screenshots/inactive-empty-en-light-390-default-top.png`.
- Configured/inactive: `screenshots/inactive-valid-tr-dark-390-default-top.png`.
- Focus alone: `screenshots/focus-valid-en-light-390-default-top.png`.
- Both owners: `screenshots/overlap-valid-en-light-390-default-top.png` (one focus hero plus background note).
- Cooldown: `screenshots/cooldown-valid-tr-dark-390-default-top.png`.
- Recovery: `screenshots/failure-valid-en-light-390-default-top.png`.
- Also included: overlapping cooldown, loading, EN/TR light/dark and 320/430pt accessibility-size top/bottom views. Native small iPhone16e and large iPhone17ProMax simulators are used, with explicit fixture width constraints.
- UI: `ui.log`, `ui.xcresult`.
- Regression pass: `regressions-isolated.log`; earlier archive failure: `regressions.log`.
- Host suites: `focus.log`, `ownership.log`, `settings.log`, `legal.log`, `terms.log`.
- Builds: `debug.log`, `release.log`; locale: `localization.log`.
- Preservation evidence: `protected-result.json`; task-only diff: `identity-only.patch`.

## Limits

Screenshots use the isolated native UI harness with explicit selection counts/runtime fixtures and lifecycle/authorization routing disabled. No opaque Apple tokens are fabricated. Actual transitions use the real ViewModel/factory/lifecycle with mock Apple/storage boundaries in host tests. This proves presentation and ownership logic, not physical-device enforcement. No real FamilyActivityPicker save, physical iPhone Screen Time, manual spoken VoiceOver or battery profiling was performed. No new animation recording is supplied because the chosen safe baseline is static.

No commit, push, branch, PR, deploy, uninstall or App Group/history deletion.
