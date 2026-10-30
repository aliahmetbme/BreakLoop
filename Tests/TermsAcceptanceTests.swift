import Foundation

@main struct TermsAcceptanceTests {
    @MainActor static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let suite = "BreakLoop.TermsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let empty = LegalPublicationConfiguration(privacy: nil, terms: nil, kvkk: nil)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let preview = TermsAcceptanceModel(defaults: defaults, configuration: empty, previewAllowed: true, now: { date })
        check(!preview.isChecked && !preview.hasAcceptedCurrentTerms, "checkbox initially unchecked")
        check(!preview.canContinue && !preview.acceptIfNeeded(), "unchecked cannot pass")
        check(preview.receipt == nil, "no implicit receipt")
        preview.isChecked = true
        check(preview.canContinue && preview.receipt == nil, "checking alone does not persist")
        check(preview.acceptIfNeeded(), "explicit continue accepts")
        check(preview.receipt?.acceptedAt == date && preview.receipt?.developmentPreview == true, "preview timestamp and marker")
        let restored = TermsAcceptanceModel(defaults: defaults, configuration: empty, previewAllowed: true)
        check(restored.hasAcceptedCurrentTerms && restored.isChecked, "receipt survives a model/relaunch reload")
        check(restored.acceptIfNeeded() && restored.receipt?.acceptedAt == date, "same version does not rewrite timestamp")
        let blocked = TermsAcceptanceModel(defaults: defaults, configuration: empty, previewAllowed: false)
        blocked.isChecked = true
        check(!blocked.canContinue && !blocked.hasAcceptedCurrentTerms && !blocked.acceptIfNeeded(), "release cannot use preview receipt or missing publications")
        // A verified Apple URL is only a non-network fixture; production URLs remain nil.
        let fixture = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        func published(_ version: String) -> LegalPublicationConfiguration {
            let doc = ReviewedLegalPublication(englishURL: fixture, turkishURL: fixture, reviewedVersion: version, reviewApproved: true)
            return LegalPublicationConfiguration(privacy: doc, terms: doc, kvkk: doc)
        }
        let final = TermsAcceptanceModel(defaults: defaults, configuration: published("terms-v1"), previewAllowed: false, now: { date.addingTimeInterval(10) })
        check(final.publicationsReady && !final.isDevelopmentPreview, "published configuration")
        check(!final.hasAcceptedCurrentTerms && !final.isChecked, "preview never counts as final acceptance")
        check(!final.canContinue, "final version must be explicitly checked")
        final.isChecked = true
        check(final.acceptIfNeeded() && final.receipt?.developmentPreview == false, "final acceptance distinct")
        check(final.receipt?.version == "terms-v1" && final.receipt?.acceptedAt == date.addingTimeInterval(10), "version and timestamp persisted")
        let same = TermsAcceptanceModel(defaults: defaults, configuration: published("terms-v1"), previewAllowed: false)
        check(same.hasAcceptedCurrentTerms && same.canContinue, "unchanged terms do not re-prompt")
        let changed = TermsAcceptanceModel(defaults: defaults, configuration: published("terms-v2"), previewAllowed: false)
        check(!changed.hasAcceptedCurrentTerms && !changed.isChecked && !changed.canContinue, "material version change requires fresh unchecked acceptance")
        changed.isChecked = true
        check(changed.acceptIfNeeded(), "new version can be accepted")
        let languageIndependent = TermsAcceptanceModel(defaults: defaults, configuration: published("terms-v2"), previewAllowed: false)
        check(languageIndependent.hasAcceptedCurrentTerms, "acceptance independent of UI language")
        let incomplete = LegalPublicationConfiguration(privacy: published("terms-v2").privacy, terms: published("terms-v2").terms, kvkk: nil)
        check(!TermsAcceptanceModel(defaults: defaults, configuration: incomplete, previewAllowed: false).canContinue, "missing required publication blocks release")
        defaults.set(Data("bad receipt".utf8), forKey: "breakloop.legal.termsAcceptance.v1")
        let corrupted = TermsAcceptanceModel(defaults: defaults, configuration: published("terms-v2"), previewAllowed: false)
        check(!corrupted.hasAcceptedCurrentTerms && !corrupted.isChecked, "corrupt receipt never grants access")
        let normal = TermsAcceptanceModel(defaults: defaults, configuration: empty)
        #if DEBUG
        check(normal.isDevelopmentPreview, "Debug enables explicit development preview")
        #else
        check(!normal.isDevelopmentPreview && normal.currentVersion == nil, "Release has no development bypass by default")
        #endif
        print("Terms acceptance: \(checks) checks passed")
    }
}
