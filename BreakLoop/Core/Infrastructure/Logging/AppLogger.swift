import Foundation
import OSLog

final class AppLogger {
    static let shared = AppLogger()
    private let persistentStore: PersistentLogStore
    private let logger = Logger(subsystem: "com.aliahmeterdogdu.BreakLoop", category: "diagnostics")
    private let processInstanceID = UUID()
    private let contextKey = "breakloop.diagnostics.operation"
    private let parentKey = "breakloop.diagnostics.parent"
    private let observationLock = NSLock()
    private var observations: [String: (String, Date)] = [:]
    private let bundle: Bundle

    init(persistentStore: PersistentLogStore = PersistentLogStore.shared, bundle: Bundle = .main) {
        self.persistentStore = persistentStore; self.bundle = bundle
    }
    func debug(_ event: String, message: String, category: LogCategory, metadata: [String: String] = [:]) {
        record(event, level: .debug, category: category, metadata: metadata)
    }
    func info(_ event: String, message: String, category: LogCategory, metadata: [String: String] = [:]) {
        record(event, level: .info, category: category, metadata: metadata)
    }
    func warning(_ event: String, message: String, category: LogCategory, metadata: [String: String] = [:]) {
        record(event, level: .warning, category: category, metadata: metadata)
    }
    func error(_ event: String, message: String, category: LogCategory, metadata: [String: String] = [:]) {
        record(event, level: .error, category: category, metadata: metadata)
    }
    func failure(_ event: String, error: Error, category: LogCategory, metadata: [String: String] = [:]) {
        var fields = metadata
        fields["originalErrorCode"] = "\((error as NSError).code)"
        fields["originalErrorDomain"] = (error as NSError).domain
        if error is SelectionFailure { fields["failureCode"] = SelectionFailure.classify(error).rawValue }
        if let value = error as? LifecycleError {
            switch value {
            case .invalidDuration: fields["failureCode"] = "invalidDuration"
            case .invalidSchedule: fields["failureCode"] = "invalidSchedule"
            case .storageUnavailable: fields["failureCode"] = "storageUnavailable"
            case .monitorUnavailable: fields["failureCode"] = "monitorUnavailable"
            }
        }
        if let recovery = error as? MonitoringRecoveryError {
            fields["failureCode"] = "runtimePersistence"
            fields["originalErrorCode"] = "\((recovery.original as NSError).code)"
            fields["originalErrorDomain"] = (recovery.original as NSError).domain
            fields["recoveryErrorCode"] = "\((recovery.persistence as NSError).code)"
            fields["recoveryErrorDomain"] = (recovery.persistence as NSError).domain
        }
        record(event, level: .error, category: category, outcome: "failed", metadata: fields)
    }
    // Synchronous context only: never leave thread-local context installed across an await.
    func withOperation(_ action: String, _ work: () throws -> Void) rethrows {
        let previous = Thread.current.threadDictionary[contextKey]
        let parent = Thread.current.threadDictionary[parentKey]
        Thread.current.threadDictionary[contextKey] = UUID().uuidString
        Thread.current.threadDictionary[parentKey] = previous
        defer { Thread.current.threadDictionary[contextKey] = previous; Thread.current.threadDictionary[parentKey] = parent }
        record(action + "_attempted", category: .lifecycle, outcome: "attempted")
        do { try work(); record(action + "_completed", category: .lifecycle, outcome: "succeeded") }
        catch { failure(action + "_failed", error: error, category: .lifecycle); throw error }
    }
    func record(_ action: String, level: LogLevel = .info, category: LogCategory,
                outcome: String = "observed", metadata: [String: String] = [:],
                before: DiagnosticRuntimeSnapshot? = nil, after: DiagnosticRuntimeSnapshot? = nil) {
        let operation = (Thread.current.threadDictionary[contextKey] as? String).flatMap(UUID.init(uuidString:))
            ?? metadata["operationId"].flatMap(UUID.init(uuidString:)) ?? UUID()
        let inferred = level == .error || action.contains("_failed") ? "failed" : ((action.contains("rejected") || metadata["result"] == "rejected") ? "rejected" : outcome)
        let entry = LogEntry(id: UUID(), timestamp: Date(), level: level, category: category,
            event: action, message: "", metadata: metadata,
            process: bundle.bundleIdentifier, processInstanceID: processInstanceID, operationID: operation,
            parentOperationID: (Thread.current.threadDictionary[parentKey] as? String).flatMap(UUID.init(uuidString:)),
            outcome: inferred, appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            sourceRevision: bundle.object(forInfoDictionaryKey: "BreakLoopSourceRevision") as? String,
            before: before, after: after).sanitized()
        if entry.outcome != "rejected", ["selection_validated", "runtime_change_signaled", "focus_restart_evaluated"].contains(action) {
            let stable = entry.metadata.filter { !["committedAtEpoch", "observedAtEpoch", "validatedAtEpoch", "signaledAt", "priorAttentionAt"].contains($0.key) }
            let key = action + (entry.metadata["stage"] ?? "")
            let fingerprint = stable.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: ";")
            observationLock.lock()
            let previous = observations[key]
            let repeated = previous?.0 == fingerprint && entry.timestamp.timeIntervalSince(previous!.1) < 60
            if !repeated { observations[key] = (fingerprint, entry.timestamp) }
            observationLock.unlock()
            if repeated { return }
        }
        // OSLog is immediate and uses the same privacy boundary as the durable archive.
        let text = "[BL][\(category.rawValue)][\(entry.event)] operation=\(operation.uuidString) outcome=\(entry.outcome ?? "unknown") \(entry.metadata)"
        if level == .error { logger.error("\(text, privacy: .public)") }
        else if level == .warning { logger.warning("\(text, privacy: .public)") }
        else if level == .debug { logger.debug("\(text, privacy: .public)") }
        else { logger.info("\(text, privacy: .public)") }
        persistentStore.append(entry)
    }
}
