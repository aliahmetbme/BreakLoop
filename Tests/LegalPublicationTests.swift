import Foundation
import SwiftUI

@main
struct LegalPublicationTests {
    @MainActor static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        let verified = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        func publication(_ english: String = "", _ turkish: String = "", version: String = "test-reviewed", approved: Bool = true) -> ReviewedLegalPublication {
            ReviewedLegalPublication(englishURL: english, turkishURL: turkish, reviewedVersion: version, reviewApproved: approved)
        }
        check(LegalPublicationConfiguration.current.destination(for: .privacy, language: "en")?.absoluteString == "https://breakloopfocusandrest.netlify.app/en/privacy", "privacy EN destination")
        check(LegalPublicationConfiguration.current.destination(for: .privacy, language: "tr")?.absoluteString == "https://breakloopfocusandrest.netlify.app/tr/privacy", "privacy TR destination")
        check(LegalPublicationConfiguration.current.destination(for: .terms, language: "en")?.absoluteString == "https://breakloopfocusandrest.netlify.app/en/terms", "terms EN destination")
        check(LegalPublicationConfiguration.current.destination(for: .terms, language: "tr")?.absoluteString == "https://breakloopfocusandrest.netlify.app/tr/terms", "terms TR destination")

        check(LegalDocument.allCases == [.privacy, .terms], "native EN/TR legal scope is Privacy and Terms only")
        let empty = LegalPublicationConfiguration(privacy: nil, terms: nil)
        for document in LegalDocument.allCases {
            check(empty.destination(for: document, language: "en") == nil, "unconfigured URLs stay blank")
            check(empty.destination(for: document, language: "tr") == nil, "unconfigured Turkish URLs stay blank")
        }
        for url in ["", "http://www.apple.com/legal", "javascript:alert(1)", "file:///tmp/legal", "https://example.com/privacy", "https://legal.example/privacy", "https://draft.test/privacy", "https://www.apple.com:443/legal", "https://user:password@www.apple.com/legal", "https://www.apple.com/legal#draft"] {
            check(publication(url, url).destination(language: "en") == nil, "unsafe or placeholder link rejected: \(url)")
        }
        check(publication(verified, verified, approved: false).destination(language: "en") == nil, "unreviewed content blocked")
        check(publication(verified, verified, version: " ").destination(language: "tr") == nil, "unversioned content blocked")
        check(publication(verified, "").destination(language: "tr") == nil, "no silent language fallback")
        check(publication(verified, verified).destination(language: "en")?.absoluteString == verified, "reviewed HTTPS document allowed")
        let config = LegalPublicationConfiguration(privacy: publication(verified, ""), terms: nil)
        let model = LegalLinksViewModel(configuration: config)
        check(model.destination(for: .privacy, locale: Locale(identifier: "en_US")) != nil, "English routing")
        check(model.destination(for: .privacy, locale: Locale(identifier: "tr_TR")) == nil, "Turkish missing publication")
        check(model.destination(for: .terms, locale: .current) == nil, "missing terms")
        model.open(URL(string: verified)!, using: OpenURLAction { _ in .discarded })
        check(model.couldNotOpen, "declined browser opening produces visible failure state")
        let success = LegalLinksViewModel(configuration: config)
        success.open(URL(string: verified)!, using: OpenURLAction { _ in .handled })
        check(!success.couldNotOpen, "accepted opening has no false error")
        // Injected handlers above never open a real browser or contact a server.
        print("Legal publication: \(checks) checks passed")
    }
}
