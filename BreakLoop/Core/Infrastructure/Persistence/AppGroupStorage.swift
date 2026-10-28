//
//  AppGroupStorage.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import Foundation
import FamilyControls

final class AppGroupStorage {
    
    static let suiteName = "group.com.aliahmeterdogdu.BreakLoop"
    
    private struct Keys {
        static let activitySelection = "activitySelection"
        static let cooldownEndDate = "cooldownEndDate"
        static let usageCheckpointState = "usageCheckpointState"
        static let cycleConfiguration = "cycleConfiguration"
        static let activeCycleSnapshot = "activeCycleSnapshot"
        static let deepFocusSession = "deepFocusSession"
        static let isBreakLoopActive = "isBreakLoopActive"
        static let appAppearance = "appAppearance"
    }
    
    private let defaults: UserDefaults
    private let runtimeStore: RuntimeFileStore?
    
    init() {
        guard let defaults = UserDefaults(
            suiteName: Self.suiteName
        ) else {
            fatalError("App Group storage could not be initialized.")
        }
        
        self.defaults = defaults
        if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.suiteName) {
            self.runtimeStore = RuntimeFileStore(directory: directory,
                migrate: { try Self.migrateRuntime(defaults: defaults) },
                didChange: {
                    let status = RuntimeChangeSignal.post()
                    AppLogger.shared.info("runtime_change_signaled", message: "Runtime transaction completed and lock released.",
                        category: .monitoring, metadata: ["signalStatus": "\(status)", "signaledAt": Date().ISO8601Format()])
                },
                didCommit: { runtime, date in
                    AppLogger.shared.info("runtime_published",
                        message: "Runtime committed: cooldown=\(runtime.cooldown?.id.uuidString ?? "none"), committedAt=\(date.timeIntervalSince1970).",
                        category: .monitoring, metadata: ["committedAtEpoch": "\(date.timeIntervalSince1970)",
                            "snapshotId": runtime.snapshot?.id.uuidString ?? "none",
                            "cooldownId": runtime.cooldown?.id.uuidString ?? "none",
                            "cooldownEnd": runtime.cooldown?.endsAt.ISO8601Format() ?? "none"])
                })
        } else { self.runtimeStore = nil }
    }
    
    func save<T: Codable>(
        _ value: T,
        forKey key: String
    ) throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: key)
    }
    
    func load<T: Codable>(
        _ type: T.Type,
        forKey key: String
    ) throws -> T? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        
        return try JSONDecoder().decode(
            type,
            from: data
        )
    }
    
    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
    
    func saveActivitySelection(
        _ selection: FamilyActivitySelection
    ) throws {
        try save (
            selection,
            forKey: Keys.activitySelection
        )
    }
    
    func loadActivitySelection() throws -> FamilyActivitySelection? {
        guard let raw = defaults.object(forKey: Keys.activitySelection) else { return nil }
        guard let data = raw as? Data else { throw SelectionFailure.corrupted }
        return try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    func loadCooldownEndDate() throws -> Date? {
        if runtimeExists { return try readRuntime().cooldown?.endsAt }
        return try load(Date.self, forKey: Keys.cooldownEndDate)
    }

    func saveCycleConfiguration(
        _ configuration: CycleConfiguration
    ) throws {
        try save(
            configuration,
            forKey: Keys.cycleConfiguration
        )
    }

    func loadCycleConfiguration() -> CycleConfiguration {
        do {
            if let config = try load(
                CycleConfiguration.self,
                forKey: Keys.cycleConfiguration
            ) {
                return config
            }
        } catch {
            // Fallback to default if decoding fails
        }
        return .default
    }

    func loadActiveCycleSnapshot() -> CycleSnapshot? {
        if runtimeExists { return try? readRuntime().snapshot }
        return try? load(CycleSnapshot.self, forKey: Keys.activeCycleSnapshot)
    }

    func loadDeepFocusSession() -> DeepFocusSession? {
        if runtimeExists { return try? readRuntime().deepFocus }
        return try? load(DeepFocusSession.self, forKey: Keys.deepFocusSession)
    }

    func isBreakLoopActive() -> Bool {
        if runtimeExists { return (try? readRuntime().snapshot) != nil }
        return defaults.bool(forKey: Keys.isBreakLoopActive)
    }

    func hasConfiguredSelection() -> Bool {
        guard let selection = try? loadActivitySelection() else {
            return false
        }
        return !selection.applicationTokens.isEmpty ||
               !selection.categoryTokens.isEmpty ||
               !selection.webDomainTokens.isEmpty
    }

    func saveAppearance(_ appearance: AppAppearance) {
        try? save(appearance.rawValue, forKey: Keys.appAppearance)
    }

    func loadAppearance() -> AppAppearance {
        guard let raw = try? load(String.self, forKey: Keys.appAppearance),
              let appearance = AppAppearance(rawValue: raw) else {
            return .system
        }
        return appearance
    }
}

enum AppAppearance: String, Codable, CaseIterable {
    case system
    case light
    case dark
}


extension AppGroupStorage: MonitoringRuntimeStore {
    private var runtimeExists: Bool {
        runtimeStore.map { FileManager.default.fileExists(atPath: $0.recordURL.path) } ?? false
    }

    private func runtimeFileStore() throws -> RuntimeFileStore {
        guard let runtimeStore else { throw LifecycleError.storageUnavailable }
        return runtimeStore
    }

    func withRuntimeLock<T>(_ body: () throws -> T) throws -> T {
        try runtimeFileStore().withRuntimeLock(body)
    }

    func readRuntime() throws -> MonitoringRuntime { try runtimeFileStore().readRuntime() }
    func writeRuntime(_ state: MonitoringRuntime) throws { try runtimeFileStore().writeRuntime(state) }

    private static func migrateRuntime(defaults: UserDefaults) throws -> MonitoringRuntime {
        func load<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try JSONDecoder().decode(type, from: data)
        }
        // One-way migration. Never discard existing configuration or legacy runtime data on upgrade.
        return MonitoringRuntime(
            snapshot: defaults.bool(forKey: Keys.isBreakLoopActive)
                ? try load(CycleSnapshot.self, forKey: Keys.activeCycleSnapshot) : nil,
            checkpoint: try load(UsageCheckpointState.self, forKey: Keys.usageCheckpointState),
            cooldown: try load(Date.self, forKey: Keys.cooldownEndDate).map { RestrictionDeadline(endsAt: $0) },
            deepFocus: try load(DeepFocusSession.self, forKey: Keys.deepFocusSession),
            legacyCooldown: true, legacyDeepFocus: true, legacyFocus: true)
    }

}
