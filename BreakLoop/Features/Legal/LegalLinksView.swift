import SwiftUI

struct LegalLinksView: View {
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @StateObject private var model = LegalLinksViewModel()
    var compact = false
    var documents: [LegalDocument] = LegalDocument.allCases
    @State private var previewDocument: LegalDocument?

    private var previewsEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BLSpacing.xxs) {
            if compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BLSpacing.sm) {
                        ForEach(documents, id: \.self) { document in
                            link(document).fixedSize(horizontal: true, vertical: true)
                        }
                    }
                    verticalLinks
                }
            } else {
                verticalLinks
            }
            if documents.contains(where: { model.destination(for: $0, locale: locale) == nil }) {
                Text(previewsEnabled
                    ? String(localized: "Development preview · final documents pending")
                    : String(localized: "Legal documents will be available once reviewed publication links are configured."))
                    .font(BLTypography.caption)
                    .foregroundStyle(BLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $previewDocument) { document in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: BLSpacing.md) {
                        Label(String(localized: "Development preview"), systemImage: "doc.text")
                            .font(BLTypography.headline)
                        Text("This is a development placeholder, not a published legal document. Final text will be added before release.")
                            .font(BLTypography.body)
                        Text("Preview acceptance is only for testing and will not count as acceptance of the final terms.")
                            .font(BLTypography.footnote)
                            .foregroundStyle(BLColor.textSecondary)
                    }
                    .frame(maxWidth: 600, alignment: .leading)
                    .padding(BLSpacing.lg)
                }
                .background(BLColor.background)
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) { previewDocument = nil }
                    }
                }
            }
        }
        .alert(String(localized: "Could not open link"), isPresented: $model.couldNotOpen) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Please try opening the document again from Settings.")
        }
    }

    private var verticalLinks: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(documents, id: \.self) { document in link(document) }
        }
    }

    private func link(_ document: LegalDocument) -> some View {
        let destination = model.destination(for: document, locale: locale)
        return Button {
            if let destination { model.open(destination, using: openURL) }
            else if previewsEnabled { previewDocument = document }
        } label: {
            HStack(spacing: BLSpacing.xxs) {
                Text(document.title)
                    .font(compact ? BLTypography.caption : BLTypography.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: destination == nil && previewsEnabled ? "doc.text" : "arrow.up.right")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(destination == nil && !previewsEnabled ? BLColor.textSecondary : BLColor.brandPrimary)
        .disabled(destination == nil && !previewsEnabled)
        .accessibilityHint(destination == nil
            ? (previewsEnabled ? String(localized: "Opens a development preview") : String(localized: "A reviewed publication link is not available yet."))
            : String(localized: "Opens in your web browser"))
    }
}

private extension LegalDocument {
    var title: String {
        switch self {
        case .privacy: return String(localized: "Privacy Policy")
        case .terms: return String(localized: "Terms of Use")
        case .kvkk: return String(localized: "KVKK Notice (Turkish)")
        }
    }
}
