//
//  LogCatagory.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 7.10.2026.
//

import Foundation

enum LogLevel: String, Codable, CaseIterable {
    case debug
    case info
    case warning
    case error
}

enum LogCategory: String, Codable, CaseIterable {
    case authorization
    case selection
    case monitoring
    case threshold
    case cooldown
    case shield
    case session
    case storage
    case lifecycle
}

struct LogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let event: String
    let message: String
    let metadata: [String: String]
    var process: String? = nil
    var processInstanceID: UUID? = nil
    var operationID: UUID? = nil
    var parentOperationID: UUID? = nil
    var schemaVersion: Int? = 1
    var outcome: String? = nil
    var appVersion: String? = nil
    var appBuild: String? = nil
    var sourceRevision: String? = nil
    var before: DiagnosticRuntimeSnapshot? = nil
    var after: DiagnosticRuntimeSnapshot? = nil

    func sanitized() -> LogEntry {
        var safe = self
        let name = DiagnosticPrivacy.action(event)
        safe = LogEntry(id: id, timestamp: timestamp, level: level, category: category, event: name,
            message: name.replacingOccurrences(of: "_", with: " "), metadata: DiagnosticPrivacy.metadata(metadata),
            process: ["com.aliahmeterdogdu.BreakLoop", "com.aliahmeterdogdu.BreakLoop.DeviceActivityMonitorExtension", "com.aliahmeterdogdu.BreakLoop.ShieldConfigurationExtension", "com.aliahmeterdogdu.BreakLoop.ShieldActionExtension"].contains(process ?? "") ? process : "legacy_or_tests",
            processInstanceID: processInstanceID, operationID: operationID ?? id, parentOperationID: parentOperationID,
            outcome: ["attempted", "succeeded", "failed", "observed", "rejected"].contains(outcome ?? "") ? outcome : "observed",
            appVersion: Self.version(appVersion), appBuild: Self.version(appBuild),
            sourceRevision: sourceRevision.flatMap { $0.count == 40 && $0.allSatisfy { $0.isHexDigit } ? $0 : nil },
            before: before, after: after)
        return safe
    }
    private static func version(_ value: String?) -> String? {
        guard let value, value.count <= 40, value.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return value
    }
}

enum DiagnosticAuthorizationStatus: String, Codable { case notSampled = "not_sampled" }

// Explicit allow-listed snapshots: never encode a FamilyActivitySelection or full runtime record.
struct DiagnosticRuntimeSnapshot: Codable, Equatable {
    let snapshotPresent: Bool
    let snapshotID: UUID?
    let snapshotStartedAt: Date?
    let usageLimitMinutes: Int?
    let restDurationMinutes: Int?
    let cooldownID: UUID?
    let cooldownEnd: Date?
    let deepFocusID: UUID?
    let deepFocusEnd: Date?
    let checkpointMinute: Int?
    let checkpointTimestamp: Date?
    let attentionResolvedAt: Date?
    let attentionCode: MonitoringFailureCode?
    let intendsShield: Bool
    // These are not authoritative runtime fields. Correlate selection/auth sampling events by operation ID.
    var authorizationStatus: DiagnosticAuthorizationStatus? = .notSampled
    var selectedApplicationCount: Int? = nil
    var selectedCategoryCount: Int? = nil
    var selectedWebsiteCount: Int? = nil

    init(_ runtime: MonitoringRuntime, at date: Date) {
        snapshotPresent = runtime.snapshot != nil; snapshotID = runtime.snapshot?.id
        snapshotStartedAt = runtime.snapshot?.startedAt; usageLimitMinutes = runtime.snapshot?.usageLimitMinutes
        restDurationMinutes = runtime.snapshot?.restDurationMinutes
        cooldownID = runtime.cooldown?.id; cooldownEnd = runtime.cooldown?.endsAt
        deepFocusID = runtime.deepFocus?.id; deepFocusEnd = runtime.deepFocus?.endsAt
        checkpointMinute = runtime.checkpoint?.usageMinute; checkpointTimestamp = runtime.checkpoint?.timestamp
        attentionCode = runtime.attention?.code; attentionResolvedAt = runtime.attention?.resolvedAt
        intendsShield = runtime.ownsShield(at: date)
    }
}

// Free-form messages/errors and arbitrary metadata are intentionally not archived or exported.
enum DiagnosticPrivacy {
    private static let knownActions: Set<String> = [
        "authorization_request_attempted", "authorization_request_completed", "authorization_request_failed",
        "app_foreground_attempted", "app_foreground_completed", "app_foreground_failed",
        "dashboard_action_attempted", "dashboard_action_completed", "dashboard_action_failed",
        "app_backgrounded", "app_foregrounded", "app_inactive", "app_launched",
        "attention_persistence_failed", "authorization_route_observed", "configuration_saved", "cooldown_early_end_ignored",
        "cooldown_end_date_missing", "cooldown_expired", "cooldown_failed", "cooldown_finished",
        "cooldown_schedule_created", "cooldown_started", "dashboard_runtime_observed", "dashboard_selection_read_failed",
        "dashboard_transition_failed", "deadline_schedule_attempted", "deadline_schedule_completed", "deadline_schedule_failed",
        "deep_focus_ended", "deep_focus_expired", "deep_focus_monitoring_started", "extend_cooldown_attempted",
        "extend_cooldown_completed", "extend_cooldown_failed", "focus_monitoring_restarted", "focus_monitoring_started",
        "focus_restart_evaluated", "focus_schedule_attempted", "focus_schedule_completed", "focus_schedule_failed",
        "interruption_persistence_failed", "interval_end_callback_attempted", "interval_end_callback_completed", "interval_end_callback_failed",
        "interval_ended", "interval_start_callback_attempted", "interval_start_callback_completed", "interval_start_callback_failed",
        "interval_started", "monitor_callback_failed", "monitoring_stop_attempted", "natural_rest_calculated",
        "natural_rest_decided", "natural_rest_detected", "normal_cycle_interrupted", "reconcile_attempted",
        "reconcile_completed", "reconcile_failed", "restored", "revocation_cleanup_failed",
        "revoked", "runtime_change_signaled", "runtime_published", "selection_missing",
        "selection_saved", "selection_validated", "setup_start_failed", "setup_stop_failed",
        "shield_action_received", "shield_applied", "shield_apply_attempted", "shield_clear_attempted",
        "shield_presented", "shield_removed", "shield_selection_failed", "stale_checkpoint_rejected",
        "stale_interval_rejected", "stale_start_rejected", "stale_threshold_rejected", "start_breakloop_attempted",
        "start_breakloop_completed", "start_breakloop_failed", "start_deep_focus_attempted", "start_deep_focus_completed",
        "start_deep_focus_failed", "status_checked", "stop_breakloop_attempted", "stop_breakloop_completed",
        "stop_breakloop_failed", "stop_deep_focus_attempted", "stop_deep_focus_completed", "stop_deep_focus_failed",
        "stopped_due_to_permission", "test_transition", "threshold_callback_attempted", "threshold_callback_completed",
        "threshold_callback_failed", "threshold_reached", "transition_failed", "unrecognized_event",
        "usage_checkpoint", "usage_checkpoint_reached", "usage_threshold_reached",
    ]
    static func action(_ value: String) -> String { knownActions.contains(value) ? value : "unrecognized_event" }
    private static let numeric = Set(["applicationTokens", "categoryTokens", "webDomainTokens", "applicationCount", "categoryCount", "usageMinute", "limitMinutes", "restMinutes", "durationMinutes", "usageLimitMinutes", "restDurationMinutes", "thresholdMinutes", "committedAtEpoch", "observedAtEpoch", "validatedAtEpoch", "attentionOccurredAt", "priorAttentionAt", "originalErrorCode", "recoveryErrorCode", "signalStatus", "checkpointCount", "minutes", "droppedEvents"])
    private static let ids = Set(["snapshotId", "cooldownId", "deepFocusId", "operationId"])
    private static let dates = Set(["cooldownEnd", "endsAt", "scheduledEndAt", "requestedEnd", "now", "observedAt", "signaledAt"])
    private static let flags = Set(["naturalRest", "cooldownExpired", "willStartFocus", "synchronized", "safeStatePersisted", "hasConfiguredSelection", "shieldAPIAttempted"])
    private static let codes = Set(["selectionMissing", "selectionCorrupted", "selectionUnsupported", "selectionUnavailable", "cooldownScheduling", "runtimePersistence", "monitorUnavailable", "invalidSchedule", "invalidDuration", "storageUnavailable", "none"])
    private static let words = Set(["accepted", "rejected", "initial", "foreground", "background", "approved", "denied", "notDetermined", "Approved", "Denied", "Not Determined", "loading", "inactive", "monitoring", "cooldown", "deepFocus", "failure", "persisted_attention", "current_synchronization", "start_focus", "prepare_shield", "save_selection", "dashboard_read", "dashboard_start", "picker_change", "manual", "invalidation", "foreground_initial", "foreground_reconciled", "foreground_recheck", "owner_deadline", "user_recovery", "action_completed", "attempted", "succeeded", "failed", "unknown"])
    static func metadata(_ input: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in input where value.count <= 128 {
            if numeric.contains(key), let number = Double(value), number.isFinite { result[key] = value }
            else if ids.contains(key), UUID(uuidString: value) != nil || value == "none" { result[key] = value }
            else if dates.contains(key), ISO8601DateFormatter().date(from: value) != nil { result[key] = value }
            else if flags.contains(key), ["true", "false"].contains(value) { result[key] = value }
            else if ["attentionCode", "failureCode", "originalFailureCode", "priorAttentionCode"].contains(key), codes.contains(value) { result[key] = value }
            else if ["stage", "reason", "mode", "failureSource", "result", "phase", "status", "sampledStatus", "previousStatus", "outcome"].contains(key), words.contains(value) { result[key] = value }
            else if ["originalErrorDomain", "errorDomain", "recoveryErrorDomain"].contains(key),
                    ["NSCocoaErrorDomain", "NSPOSIXErrorDomain", "NSOSStatusErrorDomain"].contains(value)
                    || (["originalErrorDomain", "errorDomain", "recoveryErrorDomain"].contains(key) && ["DeviceActivity.", "FamilyControls.", "com.apple.", "BreakLoop."].contains(where: value.hasPrefix)
                        && value.unicodeScalars.allSatisfy(CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains)) { result[key] = value }
            else if key == "activity" {
                let parts = value.split(separator: ".")
                if parts.count >= 2 && parts.count <= 3 && parts[0] == "breakloop" && ["focus", "cooldown", "deepFocus"].contains(String(parts[1])) && (parts.count == 2 || UUID(uuidString: String(parts[2])) != nil) { result[key] = value }
            }
        }
        return result
    }
}
