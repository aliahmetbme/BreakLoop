# Active Usage Cycle Dashboard refinement

Only the actively monitoring Dashboard presentation changes. Its primary card now shows: active badge → existing decorative ring → existing title/explanation → compact Deep Focus row → quiet Stop Usage Cycle button. The redundant monitoring caption beneath the ring is removed. Inactive experience cards, cooldown, active focus, loading and recovery paths retain their existing behavior.

The entire tinted/outlined row is one Button: scope icon, Deep Focus title, localized continuity subtitle and Start/chevron affordance. It opens the existing duration sheet through the same ViewModel method and guards. VoiceOver receives a single button, localized Start Deep Focus label, continuity value and duration-sheet hint. At accessibility text sizes the action moves beneath the title/subtitle within the same tappable row. The row has at least a 44pt content height plus padding. Stop uses the existing BLTertiaryButton with semantic secondary text; other runtime states retain their existing button components.

No lifecycle, persistence, schedule, shield, ViewModel, domain model or shared component source changed. All 58 other production Swift files match the task-start hashes. Existing monitoring motion remains enabled in production. Selection, configuration and history are not modified by the layout.

## Modified files

- `BreakLoop/Features/DashBoard/DashboardView.swift`
- `BreakLoop/Localizable.xcstrings` — Your Usage Cycle keeps running. / Kullanım Döngüsü açık kalır.; Start / Başlat.
- `Tests/DeepFocusCoexistenceUITests.swift` — contextual-row identifier, ordering, one entry, accessibility value, sheet/cancel and scrolling for larger text.
- `Tests/DeepFocusDashboardTests.swift` — three additional real ViewModel Stop assertions: inactive state, removed monitoring schedule, retained saved configuration/selection.
- This report.

## Actual verification

- Native UI suite: 9 passed, zero failures (4 monitoring/coexistence + 5 existing first-run tests). English/light/default and Turkish/dark/AX3 at 320pt include contrast, hit-region, sufficient-description and text-clipping audits. The row is below the active title, occurs once, opens the existing duration sheet and survives cancellation. Incompatible runtime states do not expose it. Inactive equal-choice tests still pass.
- Dashboard ViewModel/factory/lifecycle host tests: 29 passed, including start focus over existing cycle, failure/retry, exact snapshot/checkpoint retention, early end, re-created ViewModel and Stop.
- Full regression runner, final isolated run: 527 passed (480 lifecycle/state/archive checks + 47 logic checks), including natural focus expiry, independent cooldown ownership, delayed/reentrant callbacks and normal monitoring continuation.
- Localization: 2,004 checks passed, 319 catalog entries including bundle-specific duplicates, no missing EN/TR translations.
- Main app and all three extensions: signed generic-iOS Debug and Release builds passed on final production source. No device installation was performed.
- Screenshots: 320pt small iPhone and 430pt large iPhone, EN/TR, light/dark, standard/AX3. Accessibility-size layouts include both top and scrolled-bottom captures.
- `git diff --check` passed.

The first UI run queried the old action by label and could not locate the new grouped accessibility element. The row now explicitly exposes the button trait and uses a stable accessibility identifier; final tests passed. No lifecycle change was made to address a UI query.

### Intermittent existing diagnostic-archive test failure

The first two full regression attempts failed in the existing concurrent diagnostic-writer test: one worker reported persistence failure; another run failed to retain all 240 unique events. The final isolated run passed all 61 archive checks and the full runner. This is an unresolved intermittent test/result, not evidence that diagnostic concurrency is fixed. None of the regression runner's compiled inputs changed in this UI task. Failure logs are retained; no unrelated logger modification or weakened assertion was introduced.

## Evidence and boundaries

All artifacts remain outside the repository under `/tmp/BreakLoop-active-refinement/`:

- `ui-tests-final.log` and `ui-tests-final.xcresult`: final 9-test run.
- `dashboard-tests-final.log`: 29 host checks.
- `regressions-isolated.log`: final full pass; `regressions.log` and `regressions-final.log`: earlier archive failures.
- `localization.log`: catalog tests.
- `debug-build-final.log`, `release-build-final.log`: four-target builds.
- `protected-result.json`: unchanged production Swift files.
- `before-screenshots/`: baseline captures retained from the immediately preceding verified Dashboard implementation, including the oversized upper CTA.
- `screenshots/`: new native SwiftUI captures. Compare `active-tr-dark-430-default.png` in both screenshot folders.

The isolated UI harness in `/tmp/BreakLoop-first-run/after` supplies test selection counts/runtime, bypasses authorization/legal routing, disables Dashboard activation and decorative ambient monitoring motion, and does not fabricate opaque Apple tokens. It is not shipped. Host tests use real production ViewModels/factory/lifecycle with mock Apple/storage boundaries. Simulator screenshots and accessibility audits do not prove real-device Screen Time enforcement or manual spoken VoiceOver navigation. Physical-device validation remains outside this simulator-only session as previously requested.

No commit, push, PR or deployment.
