# Onboarding clarity and legal integration

**Later update:** The owner subsequently requested a mandatory Terms acceptance UI with deferred documents. See `Terms-Acceptance-Flow.md` for the current versioned gate, Debug-only placeholders and Release blocking. The no-checkbox results below describe the earlier iteration.

Verified locally on 30 October 2026. No commit, push, deployment or website edits were performed.

## Result

The existing logo, hero, three feature cards, soft background and Screen Time CTA remain. Shared Usage Budget now describes a repeating usage/rest cycle rather than a daily allowance. Natural Rest describes estimated time away allowing a fresh cycle; it does not say that apps reset. No extra card or onboarding page was introduced.

A compact EN/TR legal area scrolls after the feature cards, near the permission CTA. It does not increase the fixed footer. The existing safe-area inset remains for standard text; accessibility text uses the existing inline, scrollable footer. Settings exposes the same Privacy, Terms and KVKK entries. Labels wrap, touch areas are at least 44 points, decorative arrows are hidden from accessibility, and unavailable links have localized accessibility hints.

**Publication URLs are intentionally blank, as requested by the owner.** All three entries are disabled and accompanied by an explicit localized unavailable notice. No guessed domain, draft text, acceptance record or network request was added. This is integration infrastructure, not a claim that legal publication is complete.

## Source review

Read-only review used the website at `/Users/aliahmeterdogdu/Documents/ChatGPT/New project`:

- `docs/ios-proposal/BreakLoopLegalLinks.swift`: proposal only; no verified default domain. The native implementation uses String Catalogs and individual reviewed document URLs rather than its manual EN/TR strings or guessed routes.
- `lib/legal-documents.ts`, `docs/legal-source/01_privacy_en.md`, `02_privacy_tr.md`, `03_kvkk_notice_tr.md`: unresolved publication dates, retention criteria and KVKK review fields. The source Markdown explicitly identifies drafts.
- `lib/config.ts`, `lib/release.ts`, `.env.example`: EN/TR routes; KVKK is Turkish only; publication gates require verified HTTPS origin, domain ownership, legal/KVKK approval and resolved fields.
- Website Terms/License Information and `docs/legal-source/08_app_store_connect_and_review.md` point to Apple Standard EULA. Apple's published EULA URL was checked: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

No final reviewed custom contract or separate consent requirement was supplied. Final applicability remains subject to legal review and App Store Connect configuration. The website repository was not modified.

## Permission and legal distinctions

| Item | Implemented treatment |
| --- | --- |
| Apple Screen Time authorization | Existing system permission request and retry behavior; unchanged |
| Terms acceptance | No mandatory checkbox or acceptance persistence added; supplied material plans Apple Standard EULA |
| Privacy information | Separate informational document entry; no acknowledgement/acceptance inferred |
| Separate personal-data consent | Not inferred from permission or document opening; no blanket consent added |

If final legal review introduces mandatory custom Terms, implement an unchecked, independently versioned acceptance flow with timestamp and material-version renewal before release. No placeholder acceptance mechanism is shipped now. Review separately whether any distinct processing consent is actually required.

## New/modified files for this refinement

- `BreakLoop/Features/Onboarding/OnboardingView.swift`: two feature descriptions and scrollable legal/disclosure area. Existing Antigravity hero, styling and responsive footer preserved.
- `BreakLoop/Features/Settings/SettingsView.swift`: shared legal section.
- `BreakLoop/Features/Legal/LegalPublication.swift`: blank production configuration; reviewed version/approval gate; HTTPS, language and placeholder validation. English UI explicitly identifies the Turkish-only KVKK document.
- `BreakLoop/Features/Legal/LegalLinksViewModel.swift`: locale routing and URL-opening failure state.
- `BreakLoop/Features/Legal/LegalLinksView.swift`: shared adaptive link UI and localized error alert.
- `BreakLoop/Localizable.xcstrings`, `Tests/LocalizationTests.swift`: EN/TR copy and lookup assertions; concurrent existing catalog edits retained.
- `Tests/LegalPublicationTests.swift`, `Tests/run-legal-checks.sh`: 26 publication/routing/opening tests.
- `Tests/OnboardingPermissionTests.swift`, `Tests/run-onboarding-checks.sh`: 9 permission ViewModel tests.

A localization QA correction also caps the standard countdown heading width so long Turkish focus labels wrap inside the decorative dial; runtime timing is unchanged.

Other already-present local changes in project settings, colors, persistence, diagnostics, permission UI and shield translations were not reset or attributed to this refinement. The working tree advanced to `dd72323` during the session through outside activity; this task performed no Git writes.

## Verification

| Check | Result |
| --- | --- |
| Existing regression suite | 441 checks passed: lifecycle 156, synchronization 71, cooldown/selection 50, lock/termination/authorization 43, time presentation 13, archive 61, domain/layout 47 |
| Localization | 1,689 checks passed; actual compiled catalogs, EN/TR lookups, plural substitutions and bundle membership |
| Legal configuration/opening | 26 passed: blank config, unsafe/placeholder URL rejection, review/version requirements, language selection, Turkish KVKK routing, handled/discarded URL actions |
| Onboarding authorization | 9 passed: undetermined, pending, duplicate tap, denial, visible failure, retry, approval and refresh |
| Clean Debug and Release | Both succeeded for main app and all three embedded extension targets; signed device builds use build override 96178794 |
| `git diff --check` | Passed |
| UI screenshots | Native simulator fixtures, not website mockups or physical-device captures; see evidence below |

Opening tests inject SwiftUI URL handlers and perform no network requests. A handled action means dispatch was accepted, not that an HTTP page loaded. Production links remain disabled, so actual Privacy/Terms/KVKK page loading, redirects, offline handling and Safari return cannot yet be tested.

Permission tests compile the production OnboardingViewModel with its FamilyControls import removed in a temporary host copy and a mock framework boundary. They do not exercise Apple's real authorization sheet or revocation behavior on a phone.

## Screenshot evidence

Raw screenshots are outside the repository to avoid adding generated PNG clutter to Changes:

- `/tmp/BreakLoop-localization/screenshots/onboarding-tr-light-320.png` — narrow Turkish onboarding, top.
- `/tmp/BreakLoop-localization/screenshots/onboarding-tr-light-default-320-bottom.png` — narrow Turkish legal area and permission CTA.
- `/tmp/BreakLoop-localization/screenshots/onboarding-en-dark-large-440-bottom.png` — English, large text, dark, wide.
- `/tmp/BreakLoop-localization/screenshots/onboarding-tr-dark-large-320-bottom.png` — Turkish, large text, dark, narrow.
- `/tmp/BreakLoop-localization/screenshots/settings-tr-light-default-390-bottom.png` — Turkish Settings legal access.

The onboarding matrix covers EN/TR × light/dark × default/accessibility3 × 320/440-point content widths. The narrow fixture runs on iPhone 16e; the wide fixture on iPhone 17 Pro Max, both iOS 26.3. Additional default-size EN/TR screens cover permission recovery, Focus Setup, Deep Focus setup, Dashboard states and Diagnostics. Simulator fixture code and state live only under `/tmp/BreakLoop-localization/ui-project`; no harness, fake tokens or timer fixture entered the production tree. App Group access in unsigned simulator fixtures uses a temporary Documents-backed adapter; this is not proof of production App Group access or enforcement.

## Remaining blockers and acceptance

- Publish and independently verify final HTTPS EN/TR Privacy/Terms and Turkish KVKK documents, their reviewed version, redirects, content and availability. Owner explicitly deferred URLs.
- Complete legal review of draft fields, retention decisions, controller/application channel details and any transfer/consent grounds. No compliance determination was made.
- Confirm final EULA choice in App Store Connect. No custom acceptance is currently required by the supplied implementation evidence; this is not a legal opinion.
- Re-test link opening/failure and Safari return with the actual publication URLs.
- Run physical VoiceOver traversal, real permission denial/retry and system FamilyActivityPicker localization. Reduce Motion behavior was not newly exercised on a physical device.
- Physically verify per-app language switching preserves selections, active cooldown/Deep Focus, permission and diagnostic history; inspect both localized system shields.
- Current device operations timed out after an initial read-only file listing. The final build was not installed, no phone data was cleared, and no physical test is claimed.

Implementation and automated checks are ready for review. Public/TestFlight legal readiness remains blocked by intentionally absent final publication links and the outstanding physical acceptance checks.
