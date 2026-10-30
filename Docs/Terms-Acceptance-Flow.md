# Versioned Terms acceptance — development-ready UI

30 October 2026. This supersedes the earlier no-checkbox iteration in the onboarding/legal report. The owner explicitly requested a working mandatory acceptance flow before final documents are supplied, and stated this state will not be published.

## Behavior

Onboarding displays only Privacy Policy and Terms of Use, side by side when space permits; accessibility text can stack them. KVKK remains accessible in Settings. This placement change is not a determination that Turkish disclosure obligations do not apply.

- The checkbox starts unchecked. The permission/Continue CTA is disabled until checked.
- Terms acceptance is recorded only when Continue is pressed, before a Screen Time request. Denying Screen Time does not erase a separately given Terms acceptance.
- An already authorized user without the current Terms receipt sees onboarding before Dashboard. Existing monitoring, cooldown, shields and Deep Focus continue independently; no runtime cancellation or rescheduling was added.
- An unchanged accepted Terms version is not requested again. A new material Terms version starts unchecked. A UI-language change alone does not renew acceptance.
- Privacy/KVKK information remains separate. The checkbox does not record privacy acknowledgement, personal-data consent or Screen Time authorization.
- The acceptance step and CTA scroll together while acceptance is pending, including on narrow screens. This avoids an oversized fixed footer and keeps the checkbox directly above its action. Large Dynamic Type remains scrollable.

## Development preview versus Release

Production URLs remain blank. **Debug only** permits labeled placeholder sheets for the three document entries and a `development-preview-v1` acceptance. These sheets say explicitly that final legal text is pending; no invented agreement is presented as final.

Preview receipts contain `developmentPreview: true` and never satisfy the final published Terms gate. Release defaults to no preview bypass. With missing/unreviewed publication configuration, its checkbox and Continue remain unavailable. TestFlight builds normally use Release; finish publication configuration before distributing this flow for acceptance testing.

`LegalPublicationConfiguration.current` is the single configuration point. Add exact, verified EN/TR Privacy/Terms URLs and the reviewed Turkish KVKK URL via `ReviewedLegalPublication`. Set the reviewed version and approval only after actual review/publication. Increment the **Terms** `reviewedVersion` for material contractual changes; cosmetic edits should not manufacture a new acceptance requirement. Privacy document version changes alone do not invalidate an unchanged Terms receipt. Confirm the decision to use mandatory custom Terms with final legal review; this UI choice is not a compliance determination.

## Persistence

The main app uses `UserDefaults.standard`, key `breakloop.legal.termsAcceptance.v1`, containing one Codable receipt: `version`, `acceptedAt`, `developmentPreview`. The existing App Group schema, runtime files, diagnostic exports, tokens and authorization data are untouched. Corrupt/missing/stale receipts never grant Dashboard access. Local persistence is not a server-side or cryptographically signed acceptance audit.

## Files

- `BreakLoop/Features/Legal/TermsAcceptanceModel.swift`: isolated MVVM gate, versioned receipt, timestamp, preview/final distinction.
- `BreakLoop/App/AppRootView.swift`: Dashboard and permission-route access gate.
- `BreakLoop/Features/Onboarding/OnboardingView.swift`: accessible checkbox, guarded CTA, stable scrolling layout.
- `BreakLoop/Features/Legal/LegalPublication.swift`: document identity for presentation.
- `BreakLoop/Features/Legal/LegalLinksView.swift`: Debug placeholder sheets; Release retains reviewed URL-only links.
- `BreakLoop/Localizable.xcstrings`: EN/TR checkbox, states, errors and preview disclosures.
- `Tests/TermsAcceptanceTests.swift`, `Tests/run-terms-checks.sh`: 21 assertions per Debug/Release host configuration.

## Verification

- Terms gate: 21 Debug + 21 Release checks passed. Covers unchecked refusal, explicit save, reload, stable timestamp, version renewal, corrupt receipt, missing publications, preview/final separation and default Release blocking.
- Localization: 1,761 checks passed; 283 catalog entries, zero missing EN/TR values.
- Existing onboarding permission tests: 9 passed; legal link/configuration tests: 26 passed.
- Existing regression suite: 441 checks passed.
- Clean signed Debug and Release: main app plus all three extension targets, build-number override 96178795.
- `git diff --check`: passed.

Raw logs: `/tmp/BreakLoop-localization/terms-{tests,localization-tests,permission-tests,legal-tests,regressions,debug,release}.log`.

Screenshots: `/tmp/BreakLoop-localization/terms-screenshots/`, using native simulator fixtures at 320-point width. Includes unchecked/checked EN/TR, Turkish accessibility3 text and a clearly marked document placeholder. This is UI evidence, not a real legal-document reading or physical authorization test.

No physical update, data deletion, commit, push, website edit or deployment was performed. Final legal texts/publication, actual page opening/return, physical VoiceOver and end-to-end acceptance/permission tests remain release acceptance work.
