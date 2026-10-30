import SwiftUI
import Combine

@MainActor
final class LegalLinksViewModel: ObservableObject {
    @Published var couldNotOpen = false
    private let configuration: LegalPublicationConfiguration

    init(configuration: LegalPublicationConfiguration? = nil) {
        self.configuration = configuration ?? .current
    }

    func destination(for document: LegalDocument, locale: Locale) -> URL? {
        configuration.destination(for: document, language: locale.language.languageCode?.identifier ?? "en")
    }

    func open(_ url: URL, using action: OpenURLAction) {
        action(url) { [weak self] accepted in
            if !accepted { self?.couldNotOpen = true }
        }
    }
}

