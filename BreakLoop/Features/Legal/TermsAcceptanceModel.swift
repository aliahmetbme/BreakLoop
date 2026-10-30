import Foundation
import Combine

/// App-level presentation gate. Never changes Screen Time authorization or runtime ownership.
@MainActor
final class TermsAcceptanceModel: ObservableObject {
    struct Receipt: Codable, Equatable {
        let version: String
        let acceptedAt: Date
        let developmentPreview: Bool
    }

    @Published var isChecked = false
    @Published private(set) var receipt: Receipt?
    @Published private(set) var saveFailed = false
    private let defaults: UserDefaults
    private let configuration: LegalPublicationConfiguration
    private let previewAllowed: Bool
    private let now: () -> Date
    private static let receiptKey = "breakloop.legal.termsAcceptance.v1"

    init(defaults: UserDefaults = .standard, configuration: LegalPublicationConfiguration? = nil,
         previewAllowed: Bool? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.configuration = configuration ?? .current
        #if DEBUG
        self.previewAllowed = previewAllowed ?? true
        #else
        self.previewAllowed = previewAllowed ?? false
        #endif
        self.now = now
        if let data = defaults.data(forKey: Self.receiptKey) {
            receipt = try? JSONDecoder().decode(Receipt.self, from: data)
        }
        isChecked = hasAcceptedCurrentTerms
    }

    var publicationsReady: Bool {
        ["en", "tr"].allSatisfy { language in
            [LegalDocument.privacy, .terms].allSatisfy { configuration.destination(for: $0, language: language) != nil }
        }
    }
    var isDevelopmentPreview: Bool { !publicationsReady && previewAllowed }
    var currentVersion: String? {
        if publicationsReady { return configuration.terms?.reviewedVersion }
        return previewAllowed ? "development-preview-v1" : nil
    }
    var hasAcceptedCurrentTerms: Bool {
        guard let currentVersion, let receipt else { return false }
        return receipt.version == currentVersion && receipt.developmentPreview == isDevelopmentPreview
    }
    var canContinue: Bool { currentVersion != nil && (hasAcceptedCurrentTerms || isChecked) }

    @discardableResult
    func acceptIfNeeded() -> Bool {
        guard canContinue, let currentVersion else { return false }
        if hasAcceptedCurrentTerms { return true }
        let next = Receipt(version: currentVersion, acceptedAt: now(), developmentPreview: isDevelopmentPreview)
        do {
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: Self.receiptKey)
            guard defaults.data(forKey: Self.receiptKey) == data else { saveFailed = true; return false }
            receipt = next
            saveFailed = false
            return true
        } catch {
            saveFailed = true
            return false
        }
    }
}
