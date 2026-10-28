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
        var errorDescription: String? { self == .invalidOperation ? "Enter a complete operation UUID or leave it empty." : "Start date must precede end date." }
    }
}

struct DiagnosticsView: View {
    @StateObject private var model = DiagnosticsViewModel()
    @State private var confirmDelete = false
    var body: some View {
        Form {
            Section("Available History") {
                if let history = model.history {
                    if let oldest = history.oldest, let newest = history.newest {
                        Text("\(oldest.formatted()) — \(newest.formatted())")
                    } else { Text("No archived events available.") }
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(history.bytes), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(history.maximumBytes), countStyle: .file)) · target: at least \(history.retentionDays) days")
                    if let eviction = history.earlyEvictionAt {
                        Text("Storage pressure evicted history early on \(eviction.formatted()). Some requested days may be missing.")
                            .foregroundStyle(.orange)
                    }
                    if history.droppedEvents > 0 { Text("\(history.droppedEvents) events were dropped or could not be confirmed during logging failures.").foregroundStyle(.orange) }
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
                Text("Local only. Shield API attempts do not prove iOS enforcement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Filter Events") {
                DatePicker("From", selection: $model.start, displayedComponents: .date)
                DatePicker("Through", selection: $model.end, displayedComponents: .date)
                Picker("Category", selection: $model.category) {
                    Text("All").tag("all")
                    ForEach(LogCategory.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("Severity", selection: $model.severity) {
                    Text("All").tag("all")
                    ForEach(LogLevel.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                TextField("Operation UUID (optional)", text: $model.operation)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Apply Filters / Refresh") { Task { await model.reload() } }.disabled(model.busy)
            }
            Section {
                Button("Export Logs") { Task { await model.export() } }.disabled(model.busy)
            } footer: { Text("Export includes all matching retained events, not just the timeline's latest 300. Save the JSONL file to Files or iCloud Drive using the Share Sheet to keep it after uninstalling BreakLoop.") }
            Section("Recent Matching Events (up to 300)") {
                ForEach((model.history?.events ?? []).reversed()) { entry in
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(entry.event).font(.headline)
                                Text("\(entry.timestamp.formatted()) · \(entry.level.rawValue) · \(entry.category.rawValue)")
                                Text("Process: \(entry.process ?? "unknown")")
                                Text("Version: \(entry.appVersion ?? "unknown") (\(entry.appBuild ?? "unknown"))")
                                Text("Source: \(entry.sourceRevision ?? "not supplied / unverified")")
                                Text("Operation: \(entry.operationID?.uuidString ?? "unknown")").textSelection(.enabled)
                                if let parent = entry.parentOperationID { Text("Parent operation: \(parent.uuidString)").textSelection(.enabled) }
                                Text("Outcome: \(entry.outcome ?? "unknown")")
                                Text(entry.metadata.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")).textSelection(.enabled)
                                Text("Before: \(entry.before?.snapshotID?.uuidString ?? "none") · After: \(entry.after?.snapshotID?.uuidString ?? "none")")
                                Text("Export to inspect full sanitized deadlines and ownership snapshots.").font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding()
                        }.navigationTitle("Diagnostic Event")
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.event.replacingOccurrences(of: "_", with: " "))
                            Text("\(entry.timestamp.formatted()) · \(entry.level.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Delete Diagnostic History", role: .destructive) { confirmDelete = true }.disabled(model.busy)
            } footer: { Text("Deletes only diagnostics. Monitoring, selected apps and cycle configuration are preserved.") }
        }
        .navigationTitle("Diagnostics")
        .overlay { if model.busy { ProgressView() } }
        .task { await model.reload() }
        .confirmationDialog("Permanently delete local diagnostic history?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete History", role: .destructive) { Task { await model.delete() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $model.exported) { DiagnosticShareSheet(url: $0.url) }
    }
}

private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
