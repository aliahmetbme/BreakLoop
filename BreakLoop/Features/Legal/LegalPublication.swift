import Foundation

/// Release configuration only. Never use draft documents or guessed website routes.
struct ReviewedLegalPublication {
    let englishURL: String
    let turkishURL: String
    let reviewedVersion: String
    let reviewApproved: Bool

    func destination(language: String) -> URL? {
        guard reviewApproved, !reviewedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let raw = language == "tr" ? turkishURL : englishURL
        guard let components = URLComponents(string: raw),
              components.scheme == "https", let host = components.host?.lowercased(),
              host.contains("."), !host.hasSuffix(".example"), !host.hasSuffix(".test"),
              !host.hasSuffix(".invalid"), !["example.com", "example.org", "example.net"].contains(host),
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil else { return nil }
        return components.url
    }
}

enum LegalDocument: CaseIterable, Identifiable {
    case privacy, terms, kvkk
    var id: Self { self }
}

struct LegalPublicationConfiguration {
    let privacy: ReviewedLegalPublication?
    let terms: ReviewedLegalPublication?
    let kvkk: ReviewedLegalPublication?

    // Official Netlify legal endpoints verified live on October 30, 2026.
    static let current = LegalPublicationConfiguration(
        privacy: ReviewedLegalPublication(
            englishURL: "https://breakloopfocusandrest.netlify.app/en/privacy",
            turkishURL: "https://breakloopfocusandrest.netlify.app/tr/privacy",
            reviewedVersion: "2026-10-30",
            reviewApproved: true
        ),
        terms: ReviewedLegalPublication(
            englishURL: "https://breakloopfocusandrest.netlify.app/en/terms",
            turkishURL: "https://breakloopfocusandrest.netlify.app/tr/terms",
            reviewedVersion: "2026-10-30",
            reviewApproved: true
        ),
        kvkk: ReviewedLegalPublication(
            englishURL: "https://breakloopfocusandrest.netlify.app/tr/kvkk",
            turkishURL: "https://breakloopfocusandrest.netlify.app/tr/kvkk",
            reviewedVersion: "2026-10-30",
            reviewApproved: true
        )
    )

    func destination(for document: LegalDocument, language: String) -> URL? {
        switch document {
        case .privacy: return privacy?.destination(language: language)
        case .terms: return terms?.destination(language: language)
        // The supplied KVKK notice is Turkish only. Its English UI label states this explicitly.
        case .kvkk: return kvkk?.destination(language: "tr")
        }
    }
}
