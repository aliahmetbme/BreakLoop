# Dashboard, orbital, selection and legal refinement

## Result

The Dashboard uses two sibling BLCard surfaces, Usage Cycle and Deep Focus. Each has one heading/status, its own authoritative state and relevant controls. The nested focus entry and standalone Active Rule card are removed. Effective cycle durations, selected scope, configuration access, cooldown deadline/+15 minutes, focus session details and recovery actions have been relocated rather than deleted.

`DashboardState.usageCycleState` derives a temporary cycle-only presentation from the same verified runtime record. It preserves pending transitions, synchronization failures, attention and cooldown. It does not change persisted owners or introduce a new domain mode. Both active owners remain visible in separate cards. Ending/stopping one uses existing ownership-aware lifecycle methods. Starting a new focus during cooldown remains unavailable. Starting a new Usage Cycle during a standalone focus retains the prior Dashboard restriction; its inactive card explains availability after focus. No new availability policy or automatic restart was introduced.

Active cycle configuration comes from the existing snapshot via effective ViewModel values; newly configured durations remain next-cycle values. Unknown/loading/failure states do not expose normal start actions. Existing review-selection, refresh, recorded-cycle stop and retry controls remain available under their authoritative guards.

## Quiet Horizon orbital

The read-only website reference was [app/globals.css](https://github.com/aliahmetbme/BreakLoop-Website/blob/main/app/globals.css), specifically `.orbital`, `.orbital-two` and `.hero-visual:before`. The native artwork uses three thin ellipses at fixed -25°, +30° and -5° angles, a soft semantic-color radial glow and the existing infinity symbol. No CSS, dependencies, website edits or new image assets are introduced.

The artwork is 160pt normally and 120pt at accessibility sizes, with a seven-second ease-in-out scale/opacity cycle. It never spins or implies measured usage. Reduce Motion, inactive/background scenes and Low Power Mode use static artwork through the existing visibility/identity gate. The title/description and status labels remain stationary. Existing authoritative cooldown/focus countdown components are unchanged; when both real restrictions coexist, each belongs to its own card.

## One configuration path

Settings remains the canonical duration editor (Usage Limit and Break Duration). The Dashboard Usage Cycle Settings link navigates to that same Settings screen. Apps & Categories continues using the shared FamilyActivityPicker, token validation and persistence, but all UI save actions now call the existing `saveSelection()` exclusively. Its usage/rest cards, formula banner and duplicate bottom Save are removed. The navigation title is compact “Selection / Seçim”; the full Apps & Categories heading wraps in content so it remains readable on narrow phones and at accessibility sizes.

Selection save never writes CycleConfiguration, schedules monitoring, resets a checkpoint or changes shields. Existing combined ViewModel APIs were retained for compatibility; no native selection-editor control invokes them. There is one shared selection store for both experiences.

## Native legal scope

Native LegalDocument and publication configuration now contain only Privacy and Terms. Default Settings links and reviewed-publication readiness require those reviewed EN/TR documents only. KVKK labels and native catalog entries are removed. Existing HTTPS Privacy/Terms destinations, reviewed version `2026-10-30`, acceptance receipt key/version/timestamp, Debug/Release distinction and Screen Time permission separation are preserved. Tests prove a previously accepted current-version receipt is still accepted without rewriting its timestamp.

The website `/tr/kvkk` route was not modified. This UI scope change is not a legal compliance assessment or a new review of the legal text.

## Modified files

Production:
- `BreakLoop/Core/DesignSystem/Components/BLStatusRing.swift`
- `BreakLoop/Features/DashBoard/DashboardStateSynchronization.swift`
- `BreakLoop/Features/DashBoard/DashboardView.swift`
- `BreakLoop/Features/FocusSetup/FocusSetupView.swift`
- `BreakLoop/Features/Legal/LegalLinksView.swift`
- `BreakLoop/Features/Legal/LegalPublication.swift`
- `BreakLoop/Features/Legal/TermsAcceptanceModel.swift`
- `BreakLoop/Localizable.xcstrings`

Tests:
- `Tests/DeepFocusCoexistenceUITests.swift`
- `Tests/FirstRunUITests.swift`
- `Tests/FirstRunJourneyTests.swift`
- `Tests/LegalPublicationTests.swift`
- `Tests/TermsAcceptanceTests.swift`
- `Tests/LocalizationTests.swift`
- `Tests/run-first-run-checks.sh`
- `Tests/SiblingExperienceTests.swift` (new)
- `Tests/SettingsConfigurationTests.swift` (new)
- `Tests/SettingsConfigurationBoundary.swift` (new host-only dependencies)
- This report.

SettingsView/SettingsViewModel, FocusSetupViewModel, lifecycle, DeviceActivity, ManagedSettings, App Group persistence/schema and all extension artwork remain unchanged. Hash verification covers 18 core/domain/infrastructure/extension files. The task started from the current clean local tree; no reset or checkout was performed.

## Verification

- Existing regressions: 527 passed (including Dashboard synchronization, lifecycle, selection, overlapping ownership, expiry, lock/termination, diagnostics and logic checks).
- Deep Focus Dashboard: 29 passed.
- Existing first-run host journey: 34 passed, updated to selection-only save.
- New sibling/selection-isolation suite: 21 passed.
- Actual SettingsViewModel configuration save/failure suite: 10 passed (mock appearance/authorization/storage boundary).
- Legal publication/link opening success/failure: 28 passed.
- Terms acceptance: 26 Debug + 26 Release passed, including retained receipt after native KVKK removal.
- Permission denial/retry: 9 passed.
- EN/TR localization: 2,041 checks passed, 325 catalog entries including bundle-specific duplicates; no missing translations.
- Main app plus all three Screen Time extensions: final Debug and Release builds passed.
- Native UI: all 13 tests passed together on the final source, zero failures. The final combined run is recorded in `ui-final.log` and `ui-final.xcresult`. It covers two sibling cards, one focus start, sheet/cancel, overlap and cooldown controls, loading/recovery/standalone focus, selection-only editor, EN/TR legal scope, empty/ready journeys and real system Reduce Motion with foreground/background pixel checks.

Accessibility audits include contrast, hit regions, descriptions and clipping. The selection audit deliberately excludes contrast only for the disabled native Save/Kaydet button, while asserting it is disabled; no enabled content, clipping or touch-target checks are excluded. Inactive controls are an explicit [contrast-minimum exception](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html). The initial audits caught a truncated disclosure and a narrow navigation title; both were fixed. An earlier legal UI test waited for an offscreen lazy Form row before scrolling; its scroll helper was corrected. Earlier failure logs are retained.

## Evidence

Artifacts are outside the repository at `/tmp/BreakLoop-final-refinement/`:

- Baseline Dashboard: `before-screenshots/active-tr-dark.png`, `active-tr-light.png`, retained from the preceding verified implementation matching the task baseline.
- After: `screenshots/dashboard-active-valid-tr-dark-430-default-top.png` and light equivalent.
- Independent overlap: `screenshots/dashboard-overlap-valid-en-light-390-default-top.png` and Turkish equivalent.
- Matrix: 320/375/390/430pt, EN/TR, light/dark, standard/AX3, top/scrolled-bottom, empty/inactive/active/focus/cooldown/overlap/loading/failure plus Settings/selection views. Simulator hardware uses the small iPhone16e and large iPhone17ProMax; narrower widths are explicit native SwiftUI fixture constraints.
- `Quiet-Horizon-Orbital.mp4`: approximately 15 seconds of native rendering, not generated media. Frames at 2/3/4 seconds were decoded with AVFoundation and inspected.
- Logs: `regressions.log`, `deep-focus-final.log`, `first-run-final.log`, `sibling-final.log`, `settings-tests.log`, `legal.log`, `terms-final.log`, `onboarding.log`, `localization-verified.log`, `debug-final.log`, `release-final.log`, `ui-final.log`.
- `protected-result.json`: unchanged enforcement/storage source.

Reproduce host suites with `sh Tests/run-regressions.sh`, `sh Tests/run-first-run-checks.sh [Tests/SiblingExperienceTests.swift|Tests/SettingsConfigurationTests.swift|Tests/DeepFocusDashboardTests.swift]`, and the existing legal/terms/localization/onboarding runners.

The isolated UI harness is in `/tmp/BreakLoop-first-run/after`. It supplies explicit selection counts/runtime fixtures, bypasses permission/legal routing and lifecycle activation, and uses a temporary `--breathing` flag to enable artwork for the motion test/recording. It does not fabricate opaque Apple tokens. The actual native picker therefore starts empty in selection-editor screenshots; valid saves/failures are exercised with host-boundary tests. No test adapters were added to production.

## Limits

No physical-device Screen Time enforcement, real FamilyActivityPicker save, Low Power Mode hardware or battery profiling was performed. Manual spoken VoiceOver navigation was not performed; native accessibility audits and stable status/pixel checks are simulator evidence. Selection changes during an active cycle preserve the existing scheduling policy rather than rescheduling automatically; that policy still needs real-device coverage. No new legal review or legal-compliance claim is made.

No commit, push, branch, PR, deploy, uninstall or App Group/history deletion.

Final `git diff --check` passed. Final builds: `debug-final.log` / `release-final.log`. Final selection screenshots replace the earlier truncated versions; additional AX3 and overlapping-session bottom captures are included.
