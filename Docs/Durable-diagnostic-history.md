# Durable diagnostic event history

Implemented locally from HEAD `9f78a67e3f5caee21ba1a9dfa5f84dffde475e00`, October 29, 2026 (Europe/Istanbul). The initial workspace was clean. No branches, commits, pushes, PRs, remote GitHub resources or remote provisioning resources were changed.

## Investigation and architecture decisions

The previous logger retained only a 256 KiB active JSONL file and one rotated file. It rotated before taking a file lock, locked the changing data-file inode rather than a stable log lock, silently fell back to Caches, and removed the old defaults history during initialization. Those behaviors cannot reliably retain a week of cross-process history.

The existing `AppLogger`, `LogEntry` and `PersistentLogStore` remain the entry points. Their storage implementation is upgraded; no new state-management framework or monitoring architecture was added.

### Archive and limits

- App Group remains `group.com.aliahmeterdogdu.BreakLoop`.
- Archive directory: `Diagnostics-v1/` in the App Group, never Caches.
- One stable dedicated lock: `diagnostics.lock`, separate from `monitoring-runtime.lock`.
- Segments: UTC `yyyy-MM-dd.NNNNNN.jsonl`, normally bounded to 1 MiB each. Individual accepted records are bounded to 64 KiB.
- Default archive content budget: **50 MiB**, with a 4 KiB manifest reserve. `DiagnosticArchiveConfiguration` explicitly configures retention days, byte budget, segment size, queue capacity and lock timeout. Byte budgets below 8 KiB reject writes instead of silently exceeding the configured budget.
- Retention: at least **14 rolling days** when space permits. Whole UTC days older than the cutoff are removed; retaining the boundary day means up to 14 complete days plus the current partial day. The minimum configured age window is 14 days.
- Capacity pressure evicts oldest segments first. A manifest warning is saved **before** early eviction and survives restart/update. Settings displays the actual oldest/newest dates, byte usage, lost/unconfirmed events and early-eviction date. A target retention window is not falsely presented as guaranteed when capacity or I/O failures truncate history.

The budget covers the new archive files and manifest reserve. Original, pre-existing legacy sources remain in place for preservation and are not counted as newly created archive data. They stop growing under the new logger. A portable temporary export is a separate, bounded copy; export sorting and pinned read snapshots can require additional transient memory/disk space. The Settings UI maintains one export path. Filesystem allocation overhead and a copy saved by the user to Files/iCloud Drive are outside the archive content budget.

### Cross-process persistence and reads

Append, segment rotation, retention, migration and deletion acquire the same dedicated logging lock. There is no rotation outside that lock. Files are appended under the lock; interrupted tails are separated from subsequent writes. Streaming readers skip malformed/oversized/truncated lines and preserve valid surrounding events. Integrity warnings are distinct from actual pressure eviction.

Timeline/export first capture open file descriptors and lengths under the logging lock, then release it. Appends can continue while readers process the captured prefixes. Even if retention unlinks a segment, its open inode stays readable for that snapshot. Sorting, decoding and portable export run off the main thread, without keeping the log lock held for a large archive read. Exports are chronological with deterministic tie handling and deduplicate event IDs.

Legacy `breakloop.jsonl`, `breakloop.old.jsonl` and decodable `breakloop.logs` defaults arrays are imported idempotently into sanitized segments. ISO dates, prior deferred dates and millisecond dates are supported. Original sources are not deleted during initialization or migration. Malformed source data does not erase other files. Migration interruption is retried against known IDs. Explicit confirmed deletion removes diagnostic sources and writes an import tombstone so older defaults data cannot silently reappear.

### Queueing and flush behavior

`AppLogger` emits sanitized OSLog immediately and enqueues archive records. A utility queue drains batches of up to 64 from a bounded 512-event pending queue per process. Errors/warnings replace queued low-value observations under pressure. Dropped or unconfirmed records are reported. Unchanged Dashboard reads are not logged; identical accepted count/status observations are coalesced for 60 seconds. Repeated rejections retain their own counts and operation IDs.

Archive lock acquisition for a drain has a 50 ms deadline. A busy/unavailable archive does not throw into Screen Time lifecycle code or retry forever. The monitor extension gives the queue at most 50 ms to drain after its runtime operation releases the lock; shield configuration/action callbacks allow at most 30 ms. All archive I/O remains on the utility worker. Main-app logging is asynchronous, including an opportunistic background flush request. Important warning/error writes request filesystem synchronization.

**Loss limits:** sudden process termination can lose pending/in-flight records (up to 512 queued plus a 64-record batch), and OS suspension may beat an opportunistic flush. A callback's bounded flush is not an iOS process-lifetime guarantee. OSLog is supplementary and does not guarantee a week of retention. Full/unavailable storage, prolonged contention, power loss and queue overflow cannot be made lossless; these cases are surfaced rather than blocking restriction logic indefinitely. The persisted loss counter itself cannot be updated while storage is unavailable, so abrupt termination can also lose that accounting.

## Structured capture and privacy

New events carry event UUID, high-resolution wall-clock timestamp, schema version, category, coded action, outcome, process bundle identity, random process-instance UUID, operation UUID, optional parent operation UUID, app version/build and an optional supplied source revision. Nested synchronous lifecycle scopes preserve parent links; async authorization requests use an explicit operation UUID across `await`.

Source revision is accepted only as a 40-hex packaging field `BreakLoopSourceRevision`; trusted release packaging must supply a verified clean-source SHA. The code does not infer a compiled revision from a dirty checkout or invent missing provenance. The installed development build has no supplied verified source revision and the UI shows that limitation. Historical legacy entries retain original event ID/time while unavailable process/version/correlation data remains explicitly unknown or legacy-labelled.

The runtime writer captures before/after from the actual serialized predecessor and committed record under `monitoring-runtime.lock`. Its log hook only constructs sanitized values and enqueues them; it never reads/reenters runtime storage or waits for the archive lock. Snapshots include cycle presence/generation/start/configuration, cooldown/Deep Focus IDs and deadlines, checkpoint minute/time, attention/resolution and intended shield ownership. Selection counts and authorization status are sampled in their own correlated events; snapshots explicitly say authorization was not sampled rather than manufacturing an atomic authorization result.

Capture covers:

- Launch, foreground/inactive/background and authorization checks/requests/results/failures.
- Start/stop normal monitoring; focus schedule attempts/results/stops.
- Configuration/selection saves and native decoded app/category/website count validation.
- Threshold/checkpoint callbacks, Natural Rest decisions and rejected stale callbacks.
- Cooldown schedule/start, extension, expiry and cleanup; Deep Focus operations/expiry.
- Runtime publication, reconciliation and interruption/recovery failures.
- Shield presentation/action callbacks and apply/clear API attempts.

ManagedSettings writes are always **attempts**, never proof of effective system enforcement. Runtime ownership and attempted API calls are separate events.

A shared allow-list privacy boundary is applied on enqueue, write, read and export, and also protects OSLog. It excludes raw FamilyControls tokens, app/site identities, URLs, user content, arbitrary metadata, full runtime JSON, free-form messages and localized error strings that could contain paths/content. Coded action labels, numeric/typed failure codes, permitted error domains, counts, approved status words, opaque generations and explicit runtime snapshot fields remain. Unknown actions become `unrecognized_event`. Original legacy files are deliberately preserved outside the new archive; new exports never copy their raw bytes.

Wall-clock ordering is useful for chronology but is not a total cross-process causal clock. Use operation/parent IDs and authoritative before/after generations to establish transition relationships, especially if the device clock changes.

## Diagnostics interface and export

Open **Settings → Diagnostics → Event History & Export**.

1. Review available oldest/newest history, archive usage and any pressure/integrity/loss warning.
2. Choose From/Through calendar dates, category, severity and optionally a complete operation UUID.
3. Tap **Apply Filters / Refresh**. The timeline shows the latest 300 matching events; event details expose process/version, operation/parent, outcome and sanitized metadata.
4. Tap **Export Logs**. Export includes **all** matching retained events, not merely the timeline's 300. The first JSONL line is a manifest with schema, timestamp encoding, requested filters, retention/budget and loss/integrity information; subsequent lines are sanitized event objects. Dates use milliseconds since Unix epoch.
5. In the iOS Share Sheet choose Save to Files (or a Files location in iCloud Drive). A saved copy outside BreakLoop remains inspectable after the app is removed. Nothing is automatically uploaded or sent to another account.

**Delete Diagnostic History** is a separate destructive control with an explicit confirmation dialog. It touches diagnostics only, including old diagnostic sources; it does not clear selected apps, cycle configuration, monitoring runtime or shields. New functional events can be recorded after deletion.

## Example sanitized event sequence

The physical-device archive supplied a real, correlated cooldown operation:

```text
threshold_callback_attempted
usage_threshold_reached
natural_rest_decided
selection_validated                  app/category/website counts only
deadline_schedule_attempted
deadline_schedule_completed
runtime_published                    before: normal cycle; after: cooldown deadline
shield_apply_attempted               outcome: attempted, not verified enforcement
cooldown_started
runtime_change_signaled
threshold_callback_completed
```

The sanitized sample is `/tmp/BreakLoop-diagnostics-example.jsonl`. Before/after snapshots and generation/activity IDs in that file allow correlation without disclosing the selected applications.

## Exact modified files

| File | Purpose |
| --- | --- |
| `BreakLoop/Core/Infrastructure/Logging/PersistentLogStore.swift` | Bounded daily archive, dedicated lock, asynchronous priority queue, retention/pressure/integrity manifest, idempotent legacy migration, snapshot reads, export and isolated deletion. |
| `BreakLoop/Core/Infrastructure/Logging/LogCatagory.swift` | Backward-compatible event fields, coded privacy policy, explicit sanitized runtime snapshot. |
| `BreakLoop/Core/Infrastructure/Logging/AppLogger.swift` | Sanitized OSLog/archive entry point, process/version/provenance, operation/parent context, typed errors and low-value observation coalescing. |
| `BreakLoop/Core/Infrastructure/Lifecycle/RuntimeFileStore.swift` | Supplies actual before/after runtime values to the non-reentrant publication hook. |
| `BreakLoop/Core/Infrastructure/Lifecycle/MonitoringLifecycle.swift` | Correlation hook around existing transactions and explicit checkpoint/Natural Rest/cooldown/Deep Focus decision events. The original lifecycle bodies and Domain formulas are preserved. |
| `BreakLoop/Core/Infrastructure/Lifecycle/MonitoringLifecycleFactory.swift` | Connects operation context, typed schedule attempts/results/failures/stops and sanitized lifecycle events. |
| `BreakLoop/Core/Infrastructure/Persistence/AppGroupStorage.swift` | Enqueues typed publication snapshots and selection/configuration save events. |
| `BreakLoop/Core/Infrastructure/ScreenTime/ManagedSettingsService.swift` | Records apply/clear API attempts without claiming effective enforcement. |
| `BreakLoop/Core/Infrastructure/ScreenTime/ScreenTimeAuthorizationService.swift` | Async permission-request operation IDs and attempt/result/failure events. |
| `BreakLoop/App/BreakLoopApp.swift` | Launch capture. |
| `BreakLoop/App/AppRootView.swift` | Supplies the actual background versus inactive phase to logging. |
| `BreakLoop/App/AppRootViewModel.swift` | Correlated foreground capture and background/inactive flush requests; typed failures. |
| `BreakLoop/Features/DashBoard/DashboardStateSynchronization.swift` | Avoids logging unchanged observations. |
| `BreakLoop/Features/DashBoard/DashboardViewModel.swift` | Correlates explicit user actions and uses typed failure logging. |
| `BreakLoop/Features/FocusSetup/FocusSetupViewModel.swift` | Typed setup failure logging. |
| `BreakLoop/Features/Settings/SettingsView.swift` | Diagnostics navigation entry. |
| `BreakLoop/Features/Diagnostics/DiagnosticsView.swift` (new) | Date/category/severity/operation filtering, recent timeline, availability/pressure, Share Sheet export and confirmed deletion; background I/O ViewModel. |
| `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift` | Bounded post-operation flush and typed callback failures. |
| `ShieldActionExtension/ShieldActionExtension.swift` | Privacy-safe action capture and bounded flush before callback completion. |
| `ShieldConfigurationExtension/ShieldConfigurationExtension.swift` | Shield presentation capture and bounded flush. |
| `Tests/DiagnosticArchiveTests.swift` (new) | Production-source archive/privacy/concurrency/correlation/compatibility regressions. |
| `Tests/LifecycleTests.swift` | Invokes archive tests and provides separate-process logging workers. |
| `Tests/run-regressions.sh` | Compiles real logging/archive sources into the regression runner. |
| `Docs/Durable-diagnostic-history.md` (new) | This report. |

No new shared-source target membership was required: all three extensions already compile the modified logging/runtime sources. The new Diagnostics screen is app-only via its synchronized source folder. An incidental Xcode ordering-only project rewrite was removed; project membership/settings remain unchanged.

## Validation actually executed

- `sh Tests/run-regressions.sh`: **385 passed, 0 failed**: all **324 existing checks** plus **61 new diagnostics checks**.
- Coverage includes history older than seven days, the 14-day boundary, volume/capacity eviction, four independent concurrent writers, concurrent rotation/export, malformed/truncated lines and metadata, disk-full/unavailable/contended storage, queue priority, event ordering/operation/parent correlation, real authoritative before/after capture, privacy in files/exports, historical range exports, old files/defaults, update preservation, all four process identities and diagnostic deletion isolation.
- Runtime-lock isolation test holds the diagnostics lock while publishing runtime state: logging cannot reenter runtime storage or prevent the authoritative write.
- Clean unsigned Debug simulator build: **passed**, main app and all three extensions.
- Clean unsigned Debug iPhone SDK build: **passed**, all four targets.
- Signed Debug build using existing local signing profiles: **passed**, all four targets. No provisioning updates requested.
- `git diff --check`: **passed**. Existing unrelated project warnings remain.

### Physical iPhone smoke test

The signed build was installed as an update on the paired iPhone 16 Pro Max. Initial launch was refused because the device was locked. After the user unlocked it, the app launched successfully. Readback confirmed **all 143 event IDs in the copied pre-update active log** are present in the archive. The sampled archive contains 344 events, including 168 structured events and records from the main app, monitor extension and shield-action extension. No claim is made that the shield-configuration callback was exercised on the phone during this smoke test; its schema is covered by tests and its target was signed/built.

The user explicitly confirmed that **Settings → Diagnostics shows history and Export Logs opens the Share Sheet**. The actual phone-generated JSONL export was also copied back and parsed: 364 unique events, a valid portable manifest, chronological timestamps, all records within the selected range, and action-label-only messages with no raw token/selection metadata keys. Saving a copy to Files/iCloud Drive, deletion, stress performance, a real 14-day soak and every Screen Time enforcement path were not physically tested. No diagnostic history was intentionally deleted on the phone.

Artifacts:

- `/tmp/BreakLoop-diagnostics-tests.log`
- `/tmp/BreakLoop-diagnostics-simulator.log`
- `/tmp/BreakLoop-diagnostics-device.log`
- `/tmp/BreakLoop-diagnostics-signed.log`
- `/tmp/BreakLoop-diagnostics-device-install.log`
- `/tmp/BreakLoop-diagnostics-device-launch.log`
- `/tmp/BreakLoop-diagnostics-device-smoke.json`
- `/tmp/BreakLoop-diagnostics-example.jsonl`
- `/tmp/BreakLoop-diagnostics-physical-export.jsonl`

The local diff, including new files, is exported to `/tmp/BreakLoop-diagnostics.patch`. Neither staging nor committing is needed to review it.

## Remaining limits and follow-up acceptance

Already-evicted history from the former two-file logger cannot be reconstructed, and old records cannot gain fields that were never recorded. The UI shows actual available dates. A 14-day target depends on the configured budget, storage availability and process lifetime; pressure/loss/integrity warnings make gaps visible. Export may temporarily require additional space and memory proportional to the bounded archive. System data protection before first unlock can make App Group storage unavailable. Logging never resets authorization, schedules, ownership, selected apps or configuration to repair those failures.

For final physical acceptance, save a filtered historical export into Files and inspect it outside the app; test a seven-day-old real failure after a week of usage; perform a 14-day soak; repeat controlled cooldown extension/expiry and Deep Focus overlap while verifying event sequences; and test pressure/deletion on a disposable diagnostic dataset. Confirmed deletion should never be tested by wiping the only copy of useful device history.
