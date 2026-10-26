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
    }
    
    struct CycleConfiguration: Codable, Equatable {
        static let minUsageMinutes = 5
        static let maxUsageMinutes = 60
        static let minRestMinutes = 15
        static let maxRestMinutes = 60

        var usageLimitMinutes: Int
        var restDurationMinutes: Int

        static let `default` = CycleConfiguration(
            usageLimitMinutes: 20,
            restDurationMinutes: 15
        )

        init(usageLimitMinutes: Int = 20, restDurationMinutes: Int = 15) {
            self.usageLimitMinutes = max(Self.minUsageMinutes, min(Self.maxUsageMinutes, usageLimitMinutes))
            self.restDurationMinutes = max(Self.minRestMinutes, min(Self.maxRestMinutes, restDurationMinutes))
        }
    }

    struct CycleSnapshot: Codable, Equatable, Identifiable {
        let id: UUID
        let startedAt: Date
        let usageLimitMinutes: Int
        let restDurationMinutes: Int

        init(
            id: UUID = UUID(),
            startedAt: Date = Date(),
            usageLimitMinutes: Int,
            restDurationMinutes: Int
        ) {
            self.id = id
            self.startedAt = startedAt
            self.usageLimitMinutes = usageLimitMinutes
            self.restDurationMinutes = restDurationMinutes
        }

        init(configuration: CycleConfiguration, startedAt: Date = Date(), id: UUID = UUID()) {
            self.id = id
            self.startedAt = startedAt
            self.usageLimitMinutes = configuration.usageLimitMinutes
            self.restDurationMinutes = configuration.restDurationMinutes
        }
    }

    struct DeepFocusSession: Codable, Equatable, Identifiable {
        let id: UUID
        let startedAt: Date
        let endsAt: Date
        let durationMinutes: Int

        init(
            id: UUID = UUID(),
            startedAt: Date = Date(),
            durationMinutes: Int
        ) {
            self.id = id
            self.startedAt = startedAt
            self.durationMinutes = durationMinutes
            self.endsAt = startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }

        var isActive: Bool {
            Date() < endsAt
        }

        var remainingSeconds: TimeInterval {
            max(0, endsAt.timeIntervalSince(Date()))
        }
    }
    
    struct UsageCheckpointState: Codable {
        let usageMinute: Int
        let timestamp: Date
    }
    
    private let defaults: UserDefaults
    
    init() {
        guard let defaults = UserDefaults(
            suiteName: Self.suiteName
        ) else {
            fatalError("App Group storage could not be initialized.")
        }
        
        self.defaults = defaults
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
    
    func loadActivitySelection()
            throws -> FamilyActivitySelection? {

            try load(
                FamilyActivitySelection.self,
                forKey: Keys.activitySelection
            )
        }
    
    
    func saveCooldownEndDate(_ date: Date) throws {
        try save(date, forKey: Keys.cooldownEndDate)
    }

    func loadCooldownEndDate() throws -> Date? {
        try load(Date.self, forKey: Keys.cooldownEndDate)
    }

    func clearCooldownEndDate() {
        remove(forKey: Keys.cooldownEndDate)
    }
    
    func saveUsageCheckpointState(
        _ state: UsageCheckpointState
    ) throws {
        try save(
            state,
            forKey: Keys.usageCheckpointState
        )
    }

    func loadUsageCheckpointState()
    throws -> UsageCheckpointState? {
        try load(
            UsageCheckpointState.self,
            forKey: Keys.usageCheckpointState
        )
    }

    func clearUsageCheckpointState() {
        remove(
            forKey: Keys.usageCheckpointState
        )
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

    func saveActiveCycleSnapshot(_ snapshot: CycleSnapshot) throws {
        try save(snapshot, forKey: Keys.activeCycleSnapshot)
    }

    func loadActiveCycleSnapshot() -> CycleSnapshot? {
        try? load(CycleSnapshot.self, forKey: Keys.activeCycleSnapshot)
    }

    func clearActiveCycleSnapshot() {
        remove(forKey: Keys.activeCycleSnapshot)
    }

    func saveDeepFocusSession(_ session: DeepFocusSession) throws {
        try save(session, forKey: Keys.deepFocusSession)
    }

    func loadDeepFocusSession() -> DeepFocusSession? {
        try? load(DeepFocusSession.self, forKey: Keys.deepFocusSession)
    }

    func clearDeepFocusSession() {
        remove(forKey: Keys.deepFocusSession)
    }

    func setBreakLoopActive(_ isActive: Bool) {
        defaults.set(isActive, forKey: Keys.isBreakLoopActive)
    }

    func isBreakLoopActive() -> Bool {
        defaults.bool(forKey: Keys.isBreakLoopActive)
    }
}
