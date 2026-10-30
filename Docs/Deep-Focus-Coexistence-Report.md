# Deep Focus during Usage Cycle

## Finding and change

The current local tree already allowed `.monitoring` in `DashboardState.canConfigureDeepFocus`, and `MonitoringLifecycle.startDeepFocus` already retained the normal snapshot/checkpoint. The active Dashboard placed its secondary start action below the large status ring. The observed problem was discoverability/presentation; no missing lifecycle transition was found in the inspected tree.

The monitoring surface now offers one prominent Start Deep Focus action above the decorative ring. It opens the existing duration sheet without stopping Usage Cycle. The ViewModel gates presentation on supported selection/runtime and prevents duplicate presentation from clearing an existing startup error. Inactive users keep the existing equal experience cards.

While focus is foregrounded, a compact localized companion note describes the underlying persisted cycle, independently owned cooldown, or attention condition. It adds no timer, pause/freeze mechanic, percentage or persisted state. A genuinely invalidated/absent normal snapshot is never advertised as active. Early/natural focus end uses the existing lifecycle and returns to authoritative monitoring/cooldown/recovery state.

Cooldown still does not offer a new Deep Focus launch. Overlap remains possible when a normally running cycle reaches its threshold during focus; the cooldown retains independent shield ownership. Existing Natural Rest/budget progression remains unchanged.

## Files changed by this task

Production:
- `BreakLoop/Features/DashBoard/DashboardView.swift`: move action above ring, remove lower duplicate, companion note, wrapping for accessibility sizes.
- `BreakLoop/Features/DashBoard/DashboardViewModel.swift`: derived availability/companion status and duplicate/incompatible sheet-presentation guard.
- `BreakLoop/Features/DashBoard/DashboardStateSynchronization.swift`: read-only companion presentation enum; no synchronization transaction changes.
- `BreakLoop/Localizable.xcstrings`: seven EN/TR copy/accessibility strings.

Tests/tooling:
- `Tests/DeepFocusCoexistenceTests.swift`: new real-lifecycle coexistence cases.
- `Tests/DeepFocusDashboardTests.swift`: real ViewModel/factory/lifecycle cases with mock Apple/storage boundary.
- `Tests/DeepFocusCoexistenceUITests.swift`: isolated native UI tests.
- `Tests/LifecycleTests.swift`, `Tests/run-regressions.sh`: register new lifecycle suite.
- `Tests/FirstRunJourneyBoundary.swift`: injectable scheduling failure/reentrant callback and shield-clear counter.
- `Tests/run-first-run-checks.sh`: optional test entry source, preserving existing default suite.
- This report.

Pre-existing first-run Dashboard, naming, legal, onboarding and other working-tree edits are preserved. A task-only patch is saved outside the repository at `/tmp/BreakLoop-deep-focus/task-only.patch` to distinguish them from earlier local work.

## Verification

- Regression runner: 527 checks (493 existing plus 34 coexistence checks), passed.
- Real Dashboard ViewModel/factory/lifecycle host suite: 26 checks, passed.
- Existing first-run host journey: 34 checks, passed.
- Localization: 1,992 checks, 317 catalog entries including bundle-specific duplicates, passed.
- Signed generic iOS Debug and Release builds include main app, DeviceActivityMonitorExtension, ShieldConfigurationExtension and ShieldActionExtension. Build number override 96178797, without editing project version settings.
- Native UI fixture: all 9 tests passed together on the final source (4 new coexistence + 5 existing first-run tests), including English default and Turkish AX3/320pt accessibility audits. 13 screenshots cover 320/390/430pt, EN/TR, light/dark, active and overlapping states.
- `git diff --check`: passed. All 15 protected lifecycle/domain/storage/legal/onboarding/root files are byte-identical to the task baseline.

Lifecycle cases cover inactive start; focus start during monitoring; exact snapshot/checkpoint/configuration/selection preservation; early/natural focus end; delayed callbacks; normal threshold during focus; independent cooldown ownership across both end paths; schedule failure and explicit retry; foreground reconciliation; persisted runtime decode/relaunch; duplicate/reentrant start; invalid selection; and existing revocation cleanup. Dashboard tests also cover error-sheet persistence, real retry, reconstructed ViewModel, unsupported/read-failure selection and incompatible runtime states. Core revocation cleanup is tested directly; no new system-authorization behavior is claimed.

The native UI harness is isolated in `/tmp/BreakLoop-first-run/after`, outside production. It supplies explicit selection counts and runtime fixtures, bypasses permission/legal routing, disables Dashboard activation and decorative ambient monitoring motion, and never fabricates Apple opaque tokens. It tests the real SwiftUI hierarchy and accessibility, not Apple enforcement or a real FamilyActivityPicker selection. Host tests use real production state machine code with mock Apple/storage boundaries. Foreground/relaunch tests are reconstruction/reconciliation tests, not OS kill-and-restore on a phone.

Accessibility runs detected clipped Turkish helper text and then compressed button content in the active status surface at 320pt/AX3. The helper text and active surface now request their full vertical height; this also prevents title/subtitle truncation. The four new tests passed after that correction. The five existing first-run tests are also rerun against the final source.

## Limits

The user explicitly requested remaining on the Mac simulator. No device installation, runtime reset, App Group deletion, history deletion, commit, push or deployment was performed. Actual Screen Time scheduling, callbacks and shield ownership on a signed iPhone remain to be exercised in a subsequent physical-device session. Existing unrelated Swift concurrency warnings remain in Settings/Diagnostics/Appearance code; no broad refactor was made.

Artifacts/logs: `/tmp/BreakLoop-deep-focus/` (temporary, not committed).

## Final evidence

- Full native UI run: `/tmp/BreakLoop-deep-focus/ui-tests-all.log`, `/tmp/BreakLoop-deep-focus/ui-tests-all.xcresult` (9 tests, zero failures).
- Regression: `/tmp/BreakLoop-deep-focus/regressions-final.log`.
- Dashboard host: `/tmp/BreakLoop-deep-focus/dashboard-tests.log`.
- Existing journey: `/tmp/BreakLoop-deep-focus/first-run-tests.log`.
- Localization after final catalog formatting: `/tmp/BreakLoop-deep-focus/localization-final.log`.
- Four-target signed build logs: `/tmp/BreakLoop-deep-focus/debug-build-verified.log`, `/tmp/BreakLoop-deep-focus/release-build-verified.log` (both BUILD SUCCEEDED).
- Protected-file evidence: `/tmp/BreakLoop-deep-focus/protected-result.json`.
- Screenshot directory: `/tmp/BreakLoop-deep-focus/screenshots/`.
- Before: `/tmp/BreakLoop-deep-focus/before-monitoring-tr.png`.
- After monitoring: `/tmp/BreakLoop-deep-focus/screenshots/active-tr-dark-430-default.png`.
- Coexistence: `/tmp/BreakLoop-deep-focus/screenshots/overlap-tr-dark-430-default.png`.
- Narrow accessibility layout: `/tmp/BreakLoop-deep-focus/screenshots/active-tr-dark-320-large.png`.

The large iPhone simulator was left showing the final Turkish monitoring fixture. This is explicitly test data, not an actual protected Screen Time session. No simulator test adapter was added to production.
