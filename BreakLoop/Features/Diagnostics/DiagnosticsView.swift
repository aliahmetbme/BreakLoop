import SwiftUI
import Combine
import UIKit

private struct DiagnosticExport: Identifiable { let id = UUID(); let url: URL }

@MainActor
private final class DiagnosticsViewModel: ObservableObject {
    @Published var start = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @Published var end = Date()
    @Published var category = "all"
    @Published var severity = "all"
    @Published var operation = ""
    @Published var history: DiagnosticHistory?
    @Published var error: String?
    @Published var busy = false
    @Published var exported: DiagnosticExport?
    private let store = PersistentLogStore.shared
    private var revision = 0

    private func filter() throws -> DiagnosticFilter {
        let text = operation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty || UUID(uuidString: text) != nil else { throw FilterError.invalidOperation }
        guard start <= end else { throw FilterError.invalidDates }
        let first = Calendar.current.startOfDay(for: start)
        let last = (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end).addingTimeInterval(-0.001)
        return DiagnosticFilter(start: first, end: last, category: LogCategory(rawValue: category),
                                level: LogLevel(rawValue: severity), operationID: UUID(uuidString: text))
    }
    func reload() async {
        revision += 1; let current = revision; busy = true
        do {
            let filter = try filter(); let store = store
            let result = await Task.detached(priority: .utility) { store.history(filter: filter, limit: 300) }.value
            guard current == revision else { return }
            history = result; error = result.error
        } catch { self.error = error.localizedDescription }
        busy = false
    }
    func export() async {
        busy = true
        do {
            let filter = try filter(); let store = store
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("BreakLoop-diagnostics.jsonl")
            try await Task.detached(priority: .utility) { try store.export(filter: filter, destination: url) }.value
            exported = DiagnosticExport(url: url); error = nil
        } catch { self.error = error.localizedDescription }
        busy = false
    }
    func delete() async {
        busy = true
        do {
            let store = store
            try await Task.detached(priority: .utility) { try store.deleteHistory() }.value
            // The old defaults source is diagnostic-only. No selections/configuration/runtime are touched.
            UserDefaults(suiteName: AppGroupStorage.suiteName)?.removeObject(forKey: "breakloop.logs")
            error = nil
        } catch { self.error = error.localizedDescription; busy = false; return }
        busy = false
        await reload()
    }
    enum FilterError: LocalizedError {
        case invalidOperation, invalidDates
        var errorDescription: String? { self == .invalidOperation ? String(localized: "Enter a complete operation UUID or leave it empty.") : String(localized: "Start date must precede end date.") }
    }
}

struct DiagnosticsView: View {
    @StateObject private var model = DiagnosticsViewModel()
    @State private var confirmDelete = false
    var body: some View {
        Form {
            Section(String(localized: "Available History")) {
                if let history = model.history {
                    if let oldest = history.oldest, let newest = history.newest {
                        Text("\(oldest.formatted()) — \(newest.formatted())")
                    } else { Text("No archived events available.") }
                    Text(String(localized: "diagnostics.storage", defaultValue: "\(ByteCountFormatter.string(fromByteCount: Int64(history.bytes), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(history.maximumBytes), countStyle: .file)) · target: at least \(history.retentionDays) days"))
                    if let eviction = history.earlyEvictionAt {
                        Text(String(localized: "diagnostics.eviction", defaultValue: "Storage pressure evicted history early on \(eviction.formatted()). Some requested days may be missing."))
                            .foregroundStyle(.orange)
                    }
                    if history.droppedEvents > 0 { Text(String(localized: "diagnostics.dropped", defaultValue: "\(history.droppedEvents) events were dropped or could not be confirmed during logging failures.")).foregroundStyle(.orange) }
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
                Text("Local only. Shield API attempts do not prove iOS enforcement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "Filter Events")) {
                DatePicker(String(localized: "From"), selection: $model.start, displayedComponents: .date)
                DatePicker(String(localized: "Through"), selection: $model.end, displayedComponents: .date)
                Picker(String(localized: "Category"), selection: $model.category) {
                    Text("All").tag("all")
                    ForEach(LogCategory.allCases, id: \.rawValue) { Text($0.localizedTitle).tag($0.rawValue) }
                }
                Picker(String(localized: "Severity"), selection: $model.severity) {
                    Text("All").tag("all")
                    ForEach(LogLevel.allCases, id: \.rawValue) { Text($0.localizedTitle).tag($0.rawValue) }
                }
                TextField(String(localized: "Operation UUID (optional)"), text: $model.operation)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(String(localized: "Apply Filters / Refresh")) { Task { await model.reload() } }.disabled(model.busy)
            }
            Section {
                Button(String(localized: "Export Logs")) { Task { await model.export() } }.disabled(model.busy)
            } footer: { Text("Export includes all matching retained events, not just the timeline's latest 300. Save the JSONL file to Files or iCloud Drive using the Share Sheet to keep it after uninstalling BreakLoop.") }
            Section(String(localized: "Recent Matching Events (up to 300)")) {
                ForEach((model.history?.events ?? []).reversed()) { entry in
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent(String(localized: "Event Code")) { Text(verbatim: entry.event) }.font(.headline)
                                Text("\(entry.timestamp.formatted()) · \(entry.level.localizedTitle) · \(entry.category.localizedTitle)")
                                Text(String(localized: "diagnostics.process", defaultValue: "Process: \(entry.process ?? String(localized: "unknown"))"))
                                Text(String(localized: "diagnostics.version", defaultValue: "Version: \(entry.appVersion ?? String(localized: "unknown")) (\(entry.appBuild ?? String(localized: "unknown")))"))
                                Text(String(localized: "diagnostics.source", defaultValue: "Source: \(entry.sourceRevision ?? String(localized: "not supplied / unverified"))"))
                                Text(String(localized: "diagnostics.operation", defaultValue: "Operation: \(entry.operationID?.uuidString ?? String(localized: "unknown"))")).textSelection(.enabled)
                                if let parent = entry.parentOperationID { Text(String(localized: "diagnostics.parent", defaultValue: "Parent operation: \(parent.uuidString)")).textSelection(.enabled) }
                                Text(String(localized: "diagnostics.outcome", defaultValue: "Outcome: \(entry.localizedOutcome)"))
                                Text(entry.metadata.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")).textSelection(.enabled)
                                Text(String(localized: "diagnostics.beforeAfter", defaultValue: "Before: \(entry.before?.snapshotID?.uuidString ?? String(localized: "none")) · After: \(entry.after?.snapshotID?.uuidString ?? String(localized: "none"))"))
                                Text("Export to inspect full sanitized deadlines and ownership snapshots.").font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding()
                        }.navigationTitle(String(localized: "Diagnostic Event"))
                    } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: entry.event)
                            Text("\(entry.timestamp.formatted()) · \(entry.level.localizedTitle)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button(String(localized: "Delete Diagnostic History"), role: .destructive) { confirmDelete = true }.disabled(model.busy)
            } footer: { Text("Deletes only diagnostics. Monitoring, selected apps and cycle configuration are preserved.") }
        }
        .navigationTitle(String(localized: "Diagnostics"))
        .overlay { if model.busy { ProgressView() } }
        .task { await model.reload() }
        .confirmationDialog(String(localized: "Permanently delete local diagnostic history?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "Delete History"), role: .destructive) { Task { await model.delete() } }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .sheet(item: $model.exported) { DiagnosticShareSheet(url: $0.url) }
    }
}

private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// UI labels only: Codable raw values and exported identifiers never change.
private extension LogLevel {
    var localizedTitle: String {
        switch self {
        case .debug: return String(localized: "Debug")
        case .info: return String(localized: "Information")
        case .warning: return String(localized: "Warning")
        case .error: return String(localized: "Error")
        }
    }
}
private extension LogCategory {
    var localizedTitle: String {
        switch self {
        case .authorization: return String(localized: "Authorization")
        case .selection: return String(localized: "Selection")
        case .monitoring: return String(localized: "Monitoring")
        case .threshold: return String(localized: "Threshold")
        case .cooldown: return String(localized: "Cooldown")
        case .shield: return String(localized: "Shield")
        case .session: return String(localized: "Session")
        case .storage: return String(localized: "Storage")
        case .lifecycle: return String(localized: "Lifecycle")
        }
    }
}
private extension LogEntry {
    var localizedOutcome: String {
        switch outcome {
        case "attempted": return String(localized: "Attempted")
        case "succeeded": return String(localized: "Succeeded")
        case "failed": return String(localized: "Failed")
        case "observed": return String(localized: "Observed")
        case "rejected": return String(localized: "Rejected")
        case "accepted": return String(localized: "Accepted")
        default: return outcome ?? String(localized: "unknown")
        }
    }
}
