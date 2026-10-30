# First-run setup and equal feature hierarchy

30 October 2026. Clean starting commit: `aaf7b3a`. Work was performed locally; no commit, branch, push, PR or deployment.

## Result

BreakLoop remains the parent brand in the header. The two experiences are **Usage Cycle / Kullanım Döngüsü** and **Deep Focus / Derin Odak**. In configured inactive state, both use the same BLCard composition, typography, spacing and BLPrimaryButton. Neither is a secondary entry. Canonical Start/Stop/Retry labels describe Usage Cycle rather than treating BreakLoop as one of its features.

With no saved supported selection, the Dashboard shows the requested title, description and Select Apps & Categories CTA. Two compact muted previews explain what setup unlocks. These previews are informational elements, with no Button, disabled CTA, tap gesture or button accessibility trait. The large inactive status panel and suggested-schedule card no longer dominate first use.

The configured view shows two equal start cards and a compact editable selection/configuration summary. Active status rings, countdowns, cooldown extension and session controls remain authoritative. Starting Deep Focus over an already running Usage Cycle remains available as an active-state action, preserving the existing overlapping-session behavior without placing inactive start cards over an active session.

## State derivation and save journey

`DashboardExperiencePresentation` is a read-only projection of the existing `DashboardState.mode` and `DashboardSelectionState`. It is not persisted and introduces no first-launch flag or selection storage.

| Actual state | Dashboard composition |
| --- | --- |
| Inactive + empty/missing selection | Setup guidance + two informational previews |
| Inactive + supported saved selection | Two equal start cards + editable configuration summary |
| Inactive + websites or count-limit violation | Existing validation explanation + repair action + muted previews |
| Inactive + selection read failure | Saved-selection error, read-only refresh and repair action; not empty selection |
| Usage Cycle / cooldown / Deep Focus | Existing authoritative status and relevant actions; no first-use or inactive start cards |
| Loading / pending transition / recovery failure | Loading/recovery presentation outranks selection setup |

FocusSetup's existing Save path and dismissal remain unchanged. It dismisses only on successful save. The Dashboard sheet's existing `onDismiss` calls `viewModel.refresh()`, which reloads configuration and selection from existing storage and refreshes runtime without starting either experience. A missing selection clears the existing cached selection. Selection-read errors are held separately from action errors so a successful new read clears a stale read error without discarding unrelated action/runtime failures.

Saving configuration does not start Usage Cycle, Deep Focus or shield writes. Both starts still call their existing ViewModel and lifecycle methods only after explicit user action. Current support validation remains apps/categories only, up to the existing limits, with no silent website removal.

## Scope and preserved behavior

Modified production files:

- `BreakLoop/Features/DashBoard/DashboardView.swift`: state-specific first use, equal entries, summaries and current-session actions.
- `BreakLoop/Features/DashBoard/DashboardViewModel.swift`: computed presentation and separation of selection-read errors.
- `BreakLoop/Features/DashBoard/DashboardStateSynchronization.swift`: read-only projection and customer-facing recovery terminology. Synchronization/lifecycle algorithms were not refactored.
- `BreakLoop/Core/DesignSystem/Components/BLStatusBadge.swift`: Usage Cycle status naming; active text uses the existing semantic brand foreground for dark-mode readability.
- `BreakLoop/Features/FocusSetup/FocusSetupView.swift`: navigation title only, now Usage Cycle Setup.
- `BreakLoop/Features/Settings/SettingsView.swift`: Usage Cycle rule-section heading only.
- `BreakLoop/Features/Onboarding/OnboardingView.swift`: one feature-title literal changed to Usage Cycle. Permission, legal acceptance and layout/interaction flows are unchanged.
- `BreakLoop/Localizable.xcstrings`: complete EN/TR strings and canonical English Deep Focus sheet action; stable key `focus.launch` retained.

No domain type, activity name, event code, persisted key, App Group schema or ownership rule was renamed. Hash comparisons against the before snapshot confirm unchanged lifecycle implementation/factory, App Group storage, Screen Time services, Natural Rest calculators, authorization routing/ViewModel and every legal/acceptance source. See `/tmp/BreakLoop-first-run/protected-files.json`.

## Tests and actual outcomes

| Verification | Result |
| --- | --- |
| Existing starting suite | **463 checks passed**; current baseline was verified rather than assuming the older 441 count |
| Regression suite after changes | **493 checks passed**, including 30 new selection/runtime precedence assertions |
| First-run journey integration | **34 checks passed**, executing real Dashboard/FocusSetup ViewModels, configuration controller, lifecycle factory and lifecycle with injected mock Apple/storage boundaries |
| Localization | **1,950 checks passed**, 310 catalog entries, no missing EN/TR translations |
| Existing legal/permission checks | Terms acceptance 24 Debug + 24 Release, permission 9, legal publication 32; all passed without changes to their implementation |
| Native XCUITest | **5 tests passed**, including four accessibility audits and two actual editor-sheet opening/cancellation paths |
| Debug and Release | Both build the main app plus DeviceActivityMonitorExtension, ShieldConfigurationExtension and ShieldActionExtension; clean builds executed, build-number override 96178796 |
| `git diff --check` | Passed |

The integration journey covers first empty load, rejected empty save, supported selection/duration save, same-instance Dashboard refresh, no automatic scheduling, explicit Usage Cycle start/stop, Deep Focus start, overlapping Focus/Cycle ownership and return to the same cycle generation, recreation of a ViewModel with saved configuration, selection removal during active Focus/cooldown, unsupported websites, read failure/recovery, failed selection write/retry, pending transitions and persisted attention. The re-created ViewModel test is not a claim of a physical OS process relaunch with real tokens.

The native tests verify English empty setup/cancel, Turkish empty large text, English configured equal actions/focus-sheet cancel, Turkish configured large text, and unsupported/read-failure UI distinctions. Apple's actual audit checks **contrast, hit regions, sufficient element descriptions and clipped text**. It found a too-small normal-size Edit hit region. Using the existing BLTertiaryButton fixed it; the verified run passed all five tests without ignored audit issues. Large-text visual inspection also caught a compressed configuration heading; it now stacks with Edit at accessibility sizes.

Tests and runners:

- `Tests/run-regressions.sh`, `Tests/DashboardSynchronizationTests.swift`
- `Tests/run-first-run-checks.sh`, `Tests/FirstRunJourneyTests.swift`, `Tests/FirstRunJourneyBoundary.swift`
- `Tests/run-localization-checks.sh`, `Tests/LocalizationTests.swift`
- `Tests/FirstRunUITests.swift`: preserved UI-test source. It runs against the isolated fixture below, not the shipping application.

## Before/after screenshots and fixture boundaries

**4 before and 112 after captures** are retained. Native SwiftUI screenshots are under `/tmp/BreakLoop-first-run/screenshots/` rather than adding generated PNGs to Changes.

- Before empty TR: `before/empty-inactive-tr-light-390-default-top.png`
- After empty TR: `after/empty-inactive-tr-light-390-default-top.png`
- Before configured TR: `before/valid-inactive-tr-light-390-default-top.png`
- After configured TR: `after/valid-inactive-tr-light-390-default-top.png`
- Narrow setup: `after/empty-inactive-tr-light-320-default-top.png`
- Narrow configured: `after/valid-inactive-tr-light-320-default-top.png`
- Large-text summary: `after/valid-inactive-tr-dark-320-large-bottom.png`

The capture matrix covers 320/375/390/430-point content widths × EN/TR × light/dark × default/accessibility3 × empty/configured. Large-text cases also have bottom-scroll captures. Additional captures cover invalid websites, unreadable selection, active Usage Cycle, cooldown, Focus, loading and recovery with empty selection; active Usage Cycle with supported selection also retains the Focus action. Not every capture constitutes a separate manual accessibility audit.

Fixtures live only in `/tmp/BreakLoop-first-run/{before,after}`. They substitute integer **counts** for Dashboard selection presentation and seed test runtime timestamps; no opaque Apple token was fabricated. UI activation of real monitoring is disabled in the fixture. No launch-argument overrides, test target or fixture entry point was added to the production app. The temporary target was created with installed `xcodeproj`; its scheme is `FirstRunUITests`. The simulator is iOS 26.3 (iPhone 16e for widths through 390; iPhone 17 Pro Max for 430).

For this session's reproducible fixture run:

```sh
xcodebuild -project /tmp/BreakLoop-first-run/after/BreakLoop.xcodeproj \
  -scheme FirstRunUITests -configuration Debug \
  -destination 'platform=iOS Simulator,id=0EDB18DB-F6D1-4AC9-B86C-BF0003F9DA8A' \
  -derivedDataPath /tmp/BreakLoop-first-run/after-build \
  CODE_SIGNING_ALLOWED=NO test
```

Artifacts: `baseline-tests.log`, `regressions.log`, `journey-tests.log`, `localization.log`, `debug.log`, `release.log`, screenshot manifests and `ui-verification.xcresult`, all under `/tmp/BreakLoop-first-run/`. The UI result bundle records five tests / zero failures. Test fixture source preparation and screenshots are outside the repository.

## Limits and remaining physical acceptance

- The host journey mocks FamilyControls/storage/DeviceActivity boundaries; UI fixtures are not real saved application tokens or proof of Screen Time enforcement.
- Real FamilyActivityPicker selection, actual Save through the system picker, device process relaunch and a physical start/stop journey were not exercised in this task. No signed physical install or data reset was performed.
- Automated native accessibility audits passed; spoken VoiceOver/rotor behavior still needs physical user acceptance. There are no new animations; existing motion behavior and Reduce Motion handling were preserved.
- The existing configuration save still uses its existing selection write followed by configuration write. No cross-key atomicity guarantee is introduced: a later configuration-write failure can leave an earlier selection write persisted while the editor reports failure. Changing that persistence mechanism was outside this task's constraints.
- Pre-existing main-actor/default-argument, diagnostics detached-call, color-helper and App Intents metadata warnings remain; no unrelated architecture cleanup was performed.

The requested presentation and same-instance refresh flow are implemented and verified at the boundaries above. Physical Screen Time acceptance remains a separate device check; no claim of complete real-device validation is made.
