//
//  BreakLoopDomainModels.swift
//  BreakLoop
//

import Foundation

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

struct UsageCheckpointState: Codable, Equatable {
    let usageMinute: Int
    let timestamp: Date
}
