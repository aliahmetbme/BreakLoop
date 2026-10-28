# P0 stability remediation

Reviewed and edited local HEAD `678dd028e91328650fe6e0105596b744d8b2bccb` on October 28, 2026. The workspace was initially clean. No branches, commits, pushes, PRs, or remote resources were created or modified.

## Root causes and solutions

| Issue | Root cause | Implemented solution |
| --- | --- | --- |
| P0-1: cooldown extension | Only the stored date changed; the previous activity still ended at its original deadline. | Schedule a new generation while holding the shared lock, atomically publish its deadline after scheduling succeeds, then stop the old activity. Scheduling or persistence failure preserves the previous deadline and activity. End callbacks require both the current generation and an elapsed deadline. Foreground and valid interval-start reconciliation expire overdue restrictions and recover normal monitoring. |
| P0-2: normal start | Active state was written before scheduling, ignored persistence errors, and had no reliable rollback. | Schedule a unique generation under the cross-process lock before publishing a single atomic runtime record. Extension callbacks acquire that same lock and observe the committed state or reject the uncommitted generation. Failed persistence stops only the new activity. Repeated Start preserves an existing session and its checkpoint. Missing-monitor recovery clears active state if scheduling fails. |
| P0-3: Deep Focus | Session persistence and shielding preceded successful monitoring; cleanup unconditionally removed the shared shield. | Publish a Deep Focus session only after scheduling succeeds, then derive shielding from the union of unexpired cooldown and Deep Focus ownership. Failure preserves the prior runtime and shield. Early termination removes only Deep Focus ownership; normal monitoring and cooldown remain intact. |
| P0-4: stale callbacks | Static activity names and an active boolean could not distinguish generations after stop/restart. | Use snapshot/session/deadline UUIDs in activity names. Thresholds require the current focus snapshot, no cooldown, and increasing checkpoint minutes. End callbacks require the current deadline/session identity and expiration. Rejected callbacks produce structured OSLog events with non-sensitive activity identifiers. Natural Rest still uses the production calculator and rotates the cycle identity when it grants a fresh budget. |

Apple documents that callbacks may start during `startMonitoring`, stopping an ongoing activity can invoke `intervalDidEnd`, and interval dates indicate earliest delivery rather than exact delivery. The implementation does not depend on exact callback timing:

- [startMonitoring documentation](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:))
- [nextInterval documentation](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/nextinterval)

One-shot schedules use full Gregorian dates with an explicit UTC calendar/time zone. Deadlines are rounded upward to a whole second so the scheduled end matches persisted expiration without permitting an early unlock. `nextInterval` must exist, match the intended start and end, and have the expected duration. Unsupported durations or unexpected calendar interpretation throw errors instead of silently accepting a different schedule. No timer or sleeping task provides the background unlock mechanism.

## Exact changed files

| File | Purpose |
| --- | --- |
| `BreakLoop/Core/Infrastructure/Lifecycle/MonitoringLifecycle.swift` (new) | Runtime state, scheduling/commit/failure transitions, ownership, callback validation, reconciliation, and reusable schedule validation. |
| `BreakLoop/Core/Infrastructure/Lifecycle/RuntimeFileStore.swift` (new) | Atomic JSON persistence and an advisory file lock shared by app and extensions; real I/O errors propagate. |
| `BreakLoop/Core/Infrastructure/Lifecycle/MonitoringLifecycleFactory.swift` (new) | Connects lifecycle dependencies to DeviceActivity, ManagedSettings, selection/configuration storage, and OSLog. |
| `BreakLoop/Core/Infrastructure/Persistence/AppGroupStorage.swift` | Migrates legacy runtime values, exposes the shared record, and routes existing UI reads to it. Removes unused individual runtime setters to prevent partial state updates. |
| `BreakLoop/Core/Infrastructure/ScreenTime/DeviceActivityService.swift` | Generation-aware scheduling/stopping, validated absolute deadlines, and activity inventory. Keeps existing shared usage event generation. |
| `BreakLoop/Features/DashBoard/DashboardViewModel.swift` | Uses coordinated transitions, surfaces errors, and reconciles on refresh. |
| `BreakLoop/Features/FocusSetup/FocusSetupViewModel.swift` | Uses the same safe normal-start/stop path and explicit error handling. |
| `BreakLoop/Features/DashBoard/DashboardView.swift` | Refreshes dashboard state when the scene becomes active. |
| `BreakLoop/App/AppRootViewModel.swift` | Reconciles on authorized foreground entry and performs permission-revocation cleanup through the shared lock. |
| `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift` | Routes callbacks through the tested lifecycle rather than maintaining separate transition logic. |
| `BreakLoop.xcodeproj/project.pbxproj` | Adds shared lifecycle/storage files to extension target membership and the ManagedSettings adapter to the monitor extension. |
| `Tests/LifecycleTests.swift` (new) | Tests actual production lifecycle, schedule validation, and file-store implementations using controllable drivers, time and storage faults. |
| `Tests/run-regressions.sh` (new) | Compiles production sources with lifecycle regressions and runs the unchanged existing logic runner. |
| `Docs/P0-stability-remediation.md` (new) | This handoff and physical-device checklist. |

## Persistence and transition rules

App Group identifier remains `group.com.aliahmeterdogdu.BreakLoop`; named ManagedSettings store remains `breakloop.enforcement`. User selection, cycle configuration, and appearance retain their existing UserDefaults keys. Domain model schemas are unchanged.

New App Group files:

- `monitoring-runtime-v1.json`: one authoritative record containing optional `snapshot`, `checkpoint`, `cooldown` (`id`, `endsAt`), `deepFocus`, and optional `legacyCooldown`/`legacyDeepFocus` migration markers.
- `monitoring-runtime.lock`: stable lock inode, independent of the JSON file replaced on each atomic write.

On the first successful transition/reconciliation, existing runtime keys are imported. Legacy cooldown and Deep Focus activity names remain accepted for their imported deadlines; legacy focus monitoring is replaced with an identified cycle. Existing configuration is never removed. This is a one-way runtime migration: older app binaries do not understand the new authoritative file, so downgrading is not supported for an in-progress session.

Schedule and publish occur under the lock. Callbacks wait until the operation commits or fails. Successful publication precedes stopping obsolete activities and applying the derived shield. Failed starts preserve previous persisted state and stop only uncommitted generations. Stop publishes invalidation before stopping activities, preventing stop-generated callbacks from acting on a current session. Ordinary Stop BreakLoop removes normal/cooldown ownership and preserves Deep Focus; revocation clears all owners.

Cooldown completion clears its checkpoint and starts a fresh cycle from the latest configuration. Deep Focus never removes cooldown ownership or resets a valid normal session merely because Deep Focus stops. Expiration reconciliation releases expired ownership even if fresh-cycle scheduling fails, deactivating normal monitoring and surfacing/logging the scheduling error. At steady state there are at most three activities; replacing a generation briefly adds one activity before the previous one is stopped.

## Executed validation

Environment: Xcode 26.2 (17C52), iOS/iPhoneSimulator SDK 26.2.

- `sh Tests/run-regressions.sh`: **68 lifecycle/storage/schedule checks passed**, including scheduling failure, persistence failure, immediate callbacks after successful/failed publication, extension failure/success, current and obsolete early callbacks, Stop → Restart, Deep Focus termination/completion, overlapping ownership, Natural Rest, upgrade handling, corrupted records, missing-monitor recovery, and midnight/DST schedule planning.
- The file-store suite starts two independent processes that increment the same record under the actual production file lock, verifying all 60 updates are retained.
- Existing `Tests/LogicTests.swift`: **47 passed, 0 failed**, unchanged. This older runner mirrors some calculations; it is supplementary to the new tests compiled against production sources.
- Clean unsigned Debug build, `-scheme BreakLoop -sdk iphonesimulator`: **passed**, including the main app and DeviceActivityMonitorExtension, ShieldConfigurationExtension, and ShieldActionExtension.
- Clean unsigned Debug build, `-scheme BreakLoop -sdk iphoneos`: **passed**, including all four targets.
- `git diff --check`: **passed**.

Sandboxed asset compilation initially failed because simulator services were inaccessible, including during the device SDK build. Both clean builds passed when rerun with access to Xcode services. Existing warnings about actor isolation, a deprecated `onChange`, an unused mutable variable, and absent AppIntents metadata remain outside this remediation.

Build/test logs: `/tmp/BreakLoop-P0-build.log`, `/tmp/BreakLoop-P0-device.log`, `/tmp/BreakLoop-P0-tests.log`. No XCTest target existed; the regression entry point above was executed. No physical-iPhone test or signed installation was performed.

## Remaining risks and physical-iPhone checklist

Screen Time entitlement authorization, actual `nextInterval` interpretation, callback delivery, daemon activity limits, and ManagedSettings effects require a provisioned physical iPhone. Schedule validation is fail-safe: if Apple's interpretation differs, the attempted start/extension fails and preserves prior state.

Apple controls callback delivery. An overdue shield is repaired on authorized foreground entry or a valid interval-start callback; no code can promise an exact background unlock while the system withholds callbacks. If App Group storage is inaccessible or corrupted, transitions fail explicitly rather than guessing ownership. Process termination between scheduling and publication can leave an uncommitted activity, but its callbacks cannot enforce restrictions and reconciliation removes obsolete activities. Storage corruption and filesystem failure require separate recovery; they are not silently treated as an empty active session.

Manual regression checklist:

1. **Normal monitoring:** select apps and categories, start, reach checkpoints and final shared budget. Confirm one combined budget and correct cooldown. Force scheduling/persistence failures in a debug harness; verify an error and no new active snapshot/checkpoint. Repeat Start on a valid session and confirm its budget is retained.
2. **Cooldown:** extend an active cooldown, use a selected app past the old deadline, and verify it stays blocked until the new deadline. Repeat near midnight, across a DST transition, and after changing device time zone. Confirm unsupported schedules fail without changing the old deadline. At completion, confirm one fresh cycle with the latest configuration.
3. **Deep Focus:** test standalone start, natural completion and early termination; inject scheduling failure. Repeat while cooldown owns the shield and verify failed/terminated Deep Focus never releases cooldown. Let cooldown expire while Deep Focus continues and confirm shielding remains.
4. **Stop → Restart:** stop around a threshold, restart immediately, and deliver old threshold/end callbacks through the debug harness. Confirm no old budget, cooldown or shield mutation. Stop normal monitoring while Deep Focus runs and verify Deep Focus remains enforced.
5. **Relaunch/foreground:** kill and relaunch during each mode, then after its deadline while the phone was idle. Confirm configuration persists, overdue ownership clears, active Deep Focus remains shielded, and the dashboard reflects reconciled state. Repeat with permission revocation/restoration and an upgrade containing active legacy deadlines.
6. **Natural Rest:** accumulate a checkpoint, leave selected apps unused for the configured rest duration, then resume. Confirm the fresh budget uses the latest cycle configuration and callbacks from the previous snapshot are rejected.
