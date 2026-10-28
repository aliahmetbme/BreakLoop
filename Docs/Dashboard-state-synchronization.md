# Dashboard cross-process state synchronization

Reviewed local HEAD: `7c3ac52c49ae2aa71236f579c92363881b0c4481`. The workspace was clean before editing. Changes remain local and uncommitted; no branch, push, PR or remote resource was created or modified.

## Root cause and before/after behavior

Confirmed in the reviewed code:

- Dashboard runtime values were assembled from independent reads of attention, snapshot, active state, Deep Focus and cooldown. An extension publication between those reads could produce a presentation assembled from different records.
- `@Published` properties retained their previous values until another refresh. Cross-process writes had no UI invalidation mechanism. If publication occurred after the last foreground read, the Dashboard could retain its previous Active presentation.
- Root and Dashboard each reconciled on scene activation, without a shared ordering/activation guard. Dashboard refresh also reconciled during initialization, appearance and sheet dismissal.
- UI active-state mapping depended on `DeviceActivityCenter.activities`, even though inventory is lifecycle/service information rather than the authoritative persisted display mode.
- Overlap priority was inconsistent: the title, ring and actions preferred Deep Focus, but the top badge and cooldown details preferred cooldown.

In the existing lifecycle, runtime publication precedes the shield write. If the observed phone ran this implementation and the shield came from that cooldown transition, the cooldown record should already have existed before the shield appeared. However, no original device OSLog capture or exact device build identity was supplied, so the precise duration attributable to foreground rendering, extension publication or delayed UI refresh cannot be measured retrospectively. The implementation now records timestamps that separate these cases.

Before: a cached Active presentation could survive until an unrelated refresh; independently read properties and inconsistent overlap checks could disagree. After: one authoritative runtime read replaces a single Dashboard state; every badge, ring, title, deadline and normal Stop action uses that state. After a committed cooldown is observed, normal Stop is unavailable. The two deliberate +15-minute extensions still advance the deadline by 30 minutes total; their scheduling semantics are unchanged.

## Synchronization design

`DashboardStateSynchronizer` is a small main-actor helper owned by the existing Dashboard ViewModel. `DashboardState` maps one `MonitoringRuntime` to inactive, monitoring, cooldown, Deep Focus, recoverable failure or initial loading. Deep Focus takes priority over cooldown, followed by normal monitoring and inactive; unresolved attention or synchronization failure is visible without claiming a successful normal Active state. A persisted restriction remains represented until lifecycle reconciliation actually removes its ownership, rather than disappearing merely because a clock comparison elapsed.

Root and Dashboard share one ViewModel/synchronizer instance. Either can request activation; the synchronizer's active-epoch guard installs only one observer and performs one foreground reconciliation per activation. Root can activate the same instance while settings cover the Dashboard, retaining foreground recovery. The observer is installed before the initial read, followed by reconciliation and another authoritative read. Three bounded read-only checks at 0.15, 0.6 and 1.5 seconds cover a commit just after the first foreground read or a coalesced signal. None invokes lifecycle reconciliation.

The new `RuntimeChangeSignal` uses the installed SDK's public `notify_register_dispatch`/`notify_post`/`notify_cancel` Darwin APIs. The signal contains only the fixed name `com.aliahmeterdogdu.BreakLoop.runtimeChanged.v1`; it carries no selections, tokens, runtime payload or deadline. The SDK documents delivery to the requested dispatch queue; this adapter uses the main queue and bridges into the main actor. See also Apple's [Darwin notification-center documentation](https://developer.apple.com/documentation/corefoundation/cfnotificationcentergetdarwinnotifycenter()), which describes the underlying system-wide notify mechanism.

`RuntimeFileStore` tracks successful writes within the existing cross-process transaction. It posts once **after releasing the file lock**, including transactions that successfully publish failure/attention state and then throw. Failed writes do not signal success. Identical serialized records are not rewritten or signaled, preventing reconciliation feedback loops. A stable file-store instance in each `AppGroupStorage` ties writes to the corresponding locked transaction. Atomic JSON replacement and the stable lock inode remain unchanged.

Notifications only cause a fresh authoritative read. They never carry an old state to restore, reconcile, start/stop DeviceActivity, or change shielding. Duplicate records do not republish the SwiftUI state. Notifications arriving during backgrounding or from a previous activation epoch are ignored. Observer cancellation is idempotent; backgrounding, view disappearance and deallocation cancel observation, bounded rechecks and deadline work without retaining the ViewModel.

While active, a cancellable one-shot deadline task requests the existing lifecycle reconciliation and re-reads the result. It attempts each owner deadline once, so a storage/scheduling error cannot produce an infinite foreground retry loop. System DeviceActivity schedules and extension callbacks remain the background release mechanism. There is no continuous polling or foreground timer presented as a background unlock guarantee.

## Diagnostics

Use these structured events, matching generation IDs and epoch timestamps:

1. `runtime_published`: `committedAtEpoch`, `snapshotId`, `cooldownId`, `cooldownEnd`. Emitted immediately after the atomic write; its logging hook does not notify or access runtime state recursively.
2. `runtime_change_signaled`: `signalStatus` and `signaledAt`, after lock release.
3. `dashboard_runtime_observed`: `reason`, `mode`, `observedAtEpoch`, `snapshotId`, `cooldownId`, `cooldownEnd`, `synchronized`. Reasons distinguish foreground initial/reconciled/recheck, invalidation, action and owner deadline reads.

Compare `committedAtEpoch` with `observedAtEpoch` for the same cooldown ID to measure commit-to-observation lag. Compare the actual shield screenshot timestamp separately; do not infer a scheduling bug from a user-requested extended deadline. Persistent logs retain metadata, and OSLog messages include the generation/time needed to correlate events in Console. Original device timing remains a hypothesis until these logs are captured on the affected iPhone.

## Exact changed files

| File | Reason |
| --- | --- |
| `BreakLoop/Features/DashBoard/DashboardStateSynchronization.swift` (new) | Tested authoritative-state mapper, main-actor synchronization, idempotent foreground ownership, read-only invalidation/rechecks, bounded owner-deadline reconciliation and diagnostics. |
| `BreakLoop/Core/Infrastructure/Persistence/RuntimeChangeSignal.swift` (new) | Payload-free Darwin signal and cancellation token with safe cleanup; no raw observer pointers. |
| `BreakLoop/Core/Infrastructure/Lifecycle/RuntimeFileStore.swift` | Post-lock invalidation, identical-write suppression and publication timestamp hook. |
| `BreakLoop/Core/Infrastructure/Persistence/AppGroupStorage.swift` | Stable transaction file-store instance; commit/signal diagnostics; same legacy migration values and storage schema. |
| `BreakLoop/Features/DashBoard/DashboardViewModel.swift` | Publishes one runtime-derived state, exposes read-only refresh, connects signal and lifecycle dependencies, surfaces synchronization errors. |
| `BreakLoop/Features/DashBoard/DashboardView.swift` | Drives priority and Stop visibility from the shared state, handles activation/cancellation, accepts the shared ViewModel. Uses existing design components. |
| `BreakLoop/App/AppRootViewModel.swift` | Shares its Dashboard ViewModel and delegates foreground recovery to the same guarded synchronizer. |
| `BreakLoop/App/AppRootView.swift` | Injects the shared instance and forwards foreground/background lifecycle events. |
| `BreakLoop.xcodeproj/project.pbxproj` | Adds the signal infrastructure to all three extension memberships because they compile shared App Group storage. The presentation synchronizer is app-only. |
| `Tests/DashboardSynchronizationTests.swift` (new) | Tests production synchronization/mapping with the existing production lifecycle and injected scheduling, persistence, observation and time; includes actual cross-process Darwin delivery. |
| `Tests/LifecycleTests.swift` | Retains all 156 checks, adds schedule-attempt instrumentation, invokes Dashboard regressions and provides the separate-process signal test entry point. |
| `Tests/run-regressions.sh` | Compiles the real synchronization and signal sources plus their tests. |
| `Docs/Dashboard-state-synchronization.md` (new) | This investigation, implementation/verification report and device acceptance checklist. |

No runtime JSON keys, Domain formulas, cooldown extension rules, shield ownership, generation naming, interruption/rollback policy, saved selection/configuration or Design System files changed. The monitor extension already writes through shared storage, so its callback code did not need modification.

## Verification actually performed

- `sh Tests/run-regressions.sh`: **156 existing lifecycle checks passed**, **71 new Dashboard/synchronization checks passed**, and **47 existing logic checks passed, 0 failed**.
- Focused tests cover publication after the first foreground read, foreground-visible changes, duplicate/delayed signals, normal Active behavior, absence of Stop during cooldown, two +15-minute updates, stale callback/signal safety, cooldown completion, overlap priority, storage/reconciliation/observer errors, bounded retries, activation epochs, deallocation, post-lock notification ordering, unchanged/failed writes and throw-after-publication signaling.
- The integration test launches a second executable process that posts the production Darwin signal and verifies reception through the production observer on macOS. The sandbox initially denied notification service registration; the final suite passed with that service access enabled. This is macOS transport validation, not physical-iPhone Screen Time validation.
- Clean unsigned Debug builds passed with Xcode 26.2 (17C52) for both simulator SDK and iPhone SDK. The BreakLoop scheme built the main app plus DeviceActivityMonitorExtension, ShieldConfigurationExtension and ShieldActionExtension. Existing unrelated actor-isolation/Design System warnings remain; no new production warnings were introduced by these files.
- `git diff --check` passed.

Build commands: `xcodebuild -project BreakLoop.xcodeproj -scheme BreakLoop -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/BreakLoop-dashboard-simulator CODE_SIGNING_ALLOWED=NO clean build`, and the equivalent `-sdk iphoneos -derivedDataPath /tmp/BreakLoop-dashboard-device` invocation. Both ran with Xcode service access. Logs: `/tmp/BreakLoop-dashboard-tests.log`, `/tmp/BreakLoop-dashboard-simulator.log`, `/tmp/BreakLoop-dashboard-device.log`.

## Remaining timing limits and physical-iPhone acceptance

Darwin notifications are invalidation hints, not durable messages or truth. A suspended/terminated app cannot update UI until it resumes. Signals can be delayed/coalesced; foreground reads and the short read-only recheck window cover missed background signals. No finite recheck window can guarantee delivery of an arbitrarily late/lost foreground signal. Cached iOS window snapshots may briefly precede the app's first authoritative read; once the committed cooldown is observed, a single state publication removes the obsolete Active/Stop presentation.

Storage/reconciliation failures produce a recoverable presentation and do not prove restrictions were successfully refreshed. Expired-owner cleanup still depends on successful lifecycle reconciliation and documented iOS callback delivery. The tests and unsigned builds do not establish physical-device entitlement, token enforcement or exact callback timing. No provisioned iPhone was installed or tested during this task.

Use the existing **10-minute Shared Usage Budget, 15-minute cooldown and four selected apps**, without resetting configuration:

1. Reach the threshold and confirm the real custom shield appears. Open BreakLoop immediately and verify Mindful Pause/Time for a break replaces Active without an extended mismatch; correlate commit and observation logs.
2. Keep the Dashboard visible during a controlled runtime transition. Confirm a single UI mode/deadline and no duplicate DeviceActivity names.
3. Extend twice by 15 minutes. Verify +15 then +30 minutes total and continued restriction past the original deadline. Confirm an old callback cannot restore the original displayed deadline.
4. Verify automatic release at the final intended deadline, allowing for iOS callback delivery limitations, and one fresh normal cycle. Keep the app foreground at expiry and verify no stale cooldown details remain after reconciliation.
5. Repeat with backgrounding/reopening, force quitting/relaunching and a settings screen covering the Dashboard. Check observer/scheduling logs for duplicate activation or repeated activity creation.
6. Repeat with Deep Focus overlapping cooldown and a controlled read/reconciliation failure. Confirm consistent priority, actionable recovery state and preservation of valid shield ownership.
7. Save screenshots plus `runtime_published`, `runtime_change_signaled` and `dashboard_runtime_observed` events for any mismatch, including fractional epoch times and cooldown IDs.
