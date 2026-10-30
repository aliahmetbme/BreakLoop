# English/Turkish localization audit

**Later update:** Versioned Terms acceptance added 12 EN/TR entries. Current totals are 283 catalog entries and 1,761 passing localization checks; see `Terms-Acceptance-Flow.md`. The detailed counts below describe the prior audit snapshot.

30 October 2026. Current local tree, including concurrent Antigravity changes; no GitHub writes or branch/commit operations by this task.

## Architecture

English is the String Catalog source language, Turkish the additional localization. SwiftUI static labels use native localized literals; String-accepting custom components receive `String(localized:)` at their call sites. Dynamic sentences use catalog keys, complete localized phrases and typed interpolation. Multiple count parameters independently inflect in English through String Catalog substitutions; Turkish uses natural counted nouns. Date/time, byte counts and spoken durations use Foundation formatting. No language switcher, forced production locale or persisted language state was introduced.

- `BreakLoop/Localizable.xcstrings`: 241 entries, EN/TR.
- `BreakLoop/SharedErrors.xcstrings`: 23 entries, EN/TR, included in all four bundles.
- `ShieldConfigurationExtension/Localizable.xcstrings`: 7 entries, EN/TR, owned by the shield bundle.

The shield explicitly resolves its localized labels with `Bundle(for: ShieldConfigurationExtension.self)`. UIKit date formatting uses the current locale. ShieldAction `.close`, scheduling, callbacks, shield ownership and deadline calculations are not altered by localization. Historic attention is presented from stable failure codes without rewriting saved history. Diagnostic event IDs, JSON keys, metadata and raw technical values are preserved.

## Coverage

Source audit identified **245 distinct referenced app-owned localization keys** outside previews, excluding unchanged brand/version identifiers. Catalogs contain **271 entries / 270 unique keys**, including a shared title in separate bundles, dormant/template copy and previously retained variants. Counts are keys, not repeated call sites or each plural leaf. All 271 entries have reviewed-state English and Turkish values; **zero missing Turkish entries** were found. This does not claim translation of OS-provided text or arbitrary historical diagnostic values.

| Surface | Distinct referenced keys | Missing TR |
| --- | ---: | ---: |
| Onboarding / authorization | 25 | 0 |
| Dashboard / Deep Focus | 69 | 0 |
| Focus Setup / picker explanations | 26 | 0 |
| Settings | 31 | 0 |
| Diagnostics UI | 57 | 0 |
| Legal links / disclosure | 9 | 0 |
| Shared errors / archive warnings | 22 | 0 |
| Countdown / badge / accessibility | 14 | 0 |
| System shield | 7 | 0 |
| Other shared/template references | 4 | 0 |

Rows overlap through reused keys and do not sum to the unique total. Source audit details: `/tmp/BreakLoop-localization/coverage.json`.

Intentionally untranslated: BreakLoop, version/build numbers, Apple framework identifiers, event codes, UUIDs, process identifiers, structured metadata keys/values, activity identifiers, JSONL schema/timestamps and selection tokens. Preview-only sample labels are development fixtures, not runtime UI. Existing English archived diagnostic payloads are not translated or rewritten. Localized category/severity/outcome labels are presentation-only; exports keep stable raw values. System error descriptions and Apple-provided FamilyActivityPicker content remain Apple's responsibility and need physical verification.

## Resource and component audit

Clean Debug/Release products contain `en.lproj` and `tr.lproj` resources. Main app and ShieldConfigurationExtension have their own Localizable tables plus SharedErrors. DeviceActivityMonitorExtension and ShieldActionExtension include SharedErrors for their shared LocalizedError types. The main app's project known regions include `en` and `tr`; these resources support iOS system/per-app language selection, but the actual per-app Settings control was not verified on the physical phone.

Reviewed String-accepting components include BLPrimaryButton, BLSecondaryButton, BLTertiaryButton, BLPresetGrid, BLStatusBadge, BLStatusRing and onboarding feature cards. Runtime inputs are already localized at call sites; arbitrary resolved strings are not reinterpreted as catalog keys. Status/title helpers, validation messages, failure recovery and Diagnostics presentation are localized. A localized countdown-heading width cap prevents the long Turkish focus label from overflowing the decorative dial; accessibility-size layouts remain unconstrained vertically. English remains the default. Current concurrent terminology uses “Derin Odak” for Deep Focus.

## Files

Localization work covers the three catalogs, project region/resource memberships, AppRootView authorization checking, Dashboard views/ViewModel/presentation, FocusSetup, onboarding/permission UI, Settings, Diagnostics, countdown/badge components, shared LocalizedError and archive warning descriptions, and ShieldConfigurationExtension. Regression tests are `Tests/LocalizationTests.swift` and `Tests/run-localization-checks.sh`. Some localization implementation was committed externally as `1fc03c9` while this session continued; current Git diff is not a clean isolation of this task's earlier changes.

The subsequent onboarding/legal refinement and exact additional files are documented in `Onboarding-Legal-Integration-Report.md`. Existing concurrent project, color, persistence and shield-copy changes were preserved rather than reset.

## Validation

- Existing suite: **441 checks passed** on the current tree, not an assumed historical count.
- Catalog runtime/coverage suite: **1,689 checks passed** against actual `xcstringstool` compiled resources. Tests include English/Turkish lookup, extension bundle lookup, placeholders, independent plurals, preset/launch duration, shield time strings, legal labels and resource membership.
- Legal configuration: **26 checks passed**.
- Production onboarding ViewModel with mock authorization boundary: **9 checks passed**.
- Clean signed iphoneos **Debug and Release succeeded**, each building BreakLoop plus all three extensions. Build-number override: 96178794. No upload/archive distribution was performed.
- `git diff --check` passed.
- Raw logs: `/tmp/BreakLoop-localization/{debug-final.log,release-final.log,regressions-final.log,localization-tests-final.log,legal-tests-final.log,onboarding-tests.log}`.

Build warnings remain in existing main-actor/default-argument usage (AppearanceController, SettingsViewModel and Diagnostics detached calls), a pre-existing mutable local in the color helper, and App Intents metadata extraction without an AppIntents dependency. The new legal ViewModel's default-argument isolation warning was corrected; no missing-translation or placeholder compiler warning remains. These existing warnings were not fixed by unrelated architecture changes.

## UI evidence and limitations

Native simulator fixtures cover EN/TR onboarding at 320/440-point widths, light/dark, default/accessibility3, including legal content and CTA after scrolling. Additional EN/TR default-size captures cover permission recovery, Focus Setup, Deep Focus setup, Dashboard modes and Diagnostics. Raw PNGs and screenshot logs are under `/tmp/BreakLoop-localization/screenshots` and `/tmp/BreakLoop-localization/screens*.log`; they are not committed. Fixture-only rendering adapters and test runtime dates are outside the repository. No opaque FamilyControls token was fabricated.

No claim is made that every screen was visually checked in every appearance/text-size combination, that VoiceOver speech was exercised, or that physical Reduce Motion and system picker behavior passed. Simulator fixtures cannot prove Apple Screen Time enforcement. See the onboarding report for exact screenshot examples and physical checklist.

Physical device: an initial file listing succeeded, but subsequent targeted reads timed out. A root-copy attempt also encountered Apple's protected container-manager metadata file. No data was deleted or modified. The final build was not installed, and preservation across an actual language-change/update has not been proved for this build.

## Physical acceptance checklist / TestFlight blockers

- [ ] Select English and Turkish in iOS per-app language settings; confirm persistence of selection, configuration, authorization and diagnostic history.
- [ ] Switch language during active Deep Focus and cooldown; confirm runtime identity/deadlines and shield ownership remain unchanged.
- [ ] Inspect both localized system shield states, fallback and Close App behavior on a signed phone.
- [ ] Inspect FamilyActivityPicker's Apple-owned strings and BreakLoop-owned header/footer.
- [ ] Exercise VoiceOver, Reduce Motion, large text, permission denial/retry and selection/failure recovery on physical small/large phones.
- [ ] Complete real cooldown extension/expiry/restart evidence; earlier host regressions do not substitute for this.
- [ ] Publish final reviewed legal documents and fill their verified URLs; currently intentionally blank.
- [ ] Verify final distribution entitlements, App Privacy answers and other release requirements separately.

The EN/TR implementation and automated checks are ready for review. Full TestFlight acceptance is **not yet signed off**: final legal publication and the physical language/accessibility/shield checks remain outstanding.
