//
//  LogicTests.swift
//  BreakLoopTests
//
//  Self-contained, pure-logic unit test runner for BreakLoop core engine.
//

import Foundation

// MARK: - Test Framework Lite
var passedCount = 0
var failedCount = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: String = #file, line: Int = #line) {
    if actual == expected {
        passedCount += 1
        print("  ✅ PASS: \(message)")
    } else {
        failedCount += 1
        print("  ❌ FAIL: \(message)")
        print("     Expected: \(expected)")
        print("     Actual:   \(actual) (at \(file):\(line))")
    }
}

func assertTrue(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    assertEqual(condition, true, message, file: file, line: line)
}

func assertFalse(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    assertEqual(condition, false, message, file: file, line: line)
}

// MARK: - SUT Models & Logic (Mirrors Core Implementation)

struct CheckpointCalculator {
    static func checkpointStep(for limitMinutes: Int) -> Int {
        max(
            1,
            min(
                5,
                Int(ceil(Double(limitMinutes) / 12.0))
            )
        )
    }

    static func generateCheckpoints(for limitMinutes: Int) -> [Int] {
        let step = checkpointStep(for: limitMinutes)
        var result: [Int] = []
        var minute = step
        while minute < limitMinutes {
            result.append(minute)
            minute += step
        }
        return result
    }
}

struct NaturalRestCalculator {
    struct Result: Equatable {
        let wallClockSeconds: TimeInterval
        let activeUsageSeconds: TimeInterval
        let estimatedRestSeconds: TimeInterval
        let isNaturalRest: Bool
    }

    static func calculate(
        currentUsageMinute: Int,
        currentTimestamp: Date,
        previousUsageMinute: Int,
        previousTimestamp: Date,
        requiredRestMinutes: Int
    ) -> Result {
        let wallClockSeconds = currentTimestamp.timeIntervalSince(previousTimestamp)
        let requiredRestSeconds = TimeInterval(requiredRestMinutes * 60)

        guard wallClockSeconds >= requiredRestSeconds else {
            return Result(
                wallClockSeconds: max(0, wallClockSeconds),
                activeUsageSeconds: 0,
                estimatedRestSeconds: max(0, wallClockSeconds),
                isNaturalRest: false
            )
        }

        let usageDifferenceMinutes = currentUsageMinute - previousUsageMinute
        guard usageDifferenceMinutes > 0 else {
            return Result(
                wallClockSeconds: wallClockSeconds,
                activeUsageSeconds: 0,
                estimatedRestSeconds: 0,
                isNaturalRest: false
            )
        }

        let activeUsageSeconds = TimeInterval(usageDifferenceMinutes * 60)
        let estimatedRestSeconds = max(0, wallClockSeconds - activeUsageSeconds)
        let isNaturalRest = estimatedRestSeconds >= requiredRestSeconds

        return Result(
            wallClockSeconds: wallClockSeconds,
            activeUsageSeconds: activeUsageSeconds,
            estimatedRestSeconds: estimatedRestSeconds,
            isNaturalRest: isNaturalRest
        )
    }
}

struct CycleConfiguration: Codable, Equatable {
    var usageLimitMinutes: Int
    var restDurationMinutes: Int

    static let `default` = CycleConfiguration(usageLimitMinutes: 20, restDurationMinutes: 15)
}

struct CycleSnapshot: Codable, Equatable {
    let id: UUID
    let startedAt: Date
    let usageLimitMinutes: Int
    let restDurationMinutes: Int

    init(configuration: CycleConfiguration, startedAt: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.startedAt = startedAt
        self.usageLimitMinutes = configuration.usageLimitMinutes
        self.restDurationMinutes = configuration.restDurationMinutes
    }
}

struct DeepFocusSession: Codable, Equatable {
    let id: UUID
    let startedAt: Date
    let endsAt: Date
    let durationMinutes: Int

    init(id: UUID = UUID(), startedAt: Date = Date(), durationMinutes: Int) {
        self.id = id
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes
        self.endsAt = startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    var isActive: Bool {
        Date() < endsAt
    }
}

// MARK: - Test Cases

print("=== RUNNING BREAKLOOP LOGIC TESTS ===")

// 1. Checkpoint Generation Tests
print("\n[Suite 1: Checkpoint Generation]")
let checkpoints5m = CheckpointCalculator.generateCheckpoints(for: 5)
assertEqual(checkpoints5m, [1, 2, 3, 4], "5 min limit produces 1, 2, 3, 4 checkpoints (step 1m)")

let checkpoints20m = CheckpointCalculator.generateCheckpoints(for: 20)
assertEqual(checkpoints20m, [2, 4, 6, 8, 10, 12, 14, 16, 18], "20 min limit produces step 2m checkpoints up to 18")

let checkpoints60m = CheckpointCalculator.generateCheckpoints(for: 60)
assertEqual(checkpoints60m, [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], "60 min limit produces step 5m checkpoints up to 55")

// 2. Natural Rest Calculation Tests
print("\n[Suite 2: Natural Rest Calculation]")
let t0 = Date(timeIntervalSince1970: 100000)

// Case A: 3 min break -> wallClock 4 min (240s), active 1 min (60s), rest 180s < 900s
let t1 = t0.addingTimeInterval(240)
let rest3m = NaturalRestCalculator.calculate(
    currentUsageMinute: 4,
    currentTimestamp: t1,
    previousUsageMinute: 3,
    previousTimestamp: t0,
    requiredRestMinutes: 15
)
assertFalse(rest3m.isNaturalRest, "3 min break is NOT natural rest (estimated 3m < 15m)")

// Case B: 15 min break -> wallClock 16 min (960s), active 1 min (60s), rest 900s == 900s
let t2 = t0.addingTimeInterval(960)
let rest15m = NaturalRestCalculator.calculate(
    currentUsageMinute: 4,
    currentTimestamp: t2,
    previousUsageMinute: 3,
    previousTimestamp: t0,
    requiredRestMinutes: 15
)
assertTrue(rest15m.isNaturalRest, "15 min break IS natural rest (estimated 15m >= 15m)")
assertEqual(rest15m.estimatedRestSeconds, 900, "Estimated rest is exactly 900 seconds (15 min)")

// Case C: 20 min break -> wallClock 21 min (1260s), active 1 min (60s), rest 1200s > 900s
let t3 = t0.addingTimeInterval(1260)
let rest20m = NaturalRestCalculator.calculate(
    currentUsageMinute: 4,
    currentTimestamp: t3,
    previousUsageMinute: 3,
    previousTimestamp: t0,
    requiredRestMinutes: 15
)
assertTrue(rest20m.isNaturalRest, "20 min break IS natural rest (estimated 20m >= 15m)")
assertEqual(rest20m.estimatedRestSeconds, 1200, "Estimated rest is 1200 seconds (20 min)")

// 3. CycleSnapshot Isolation Tests
print("\n[Suite 3: CycleSnapshot Isolation]")
var currentConfig = CycleConfiguration(usageLimitMinutes: 20, restDurationMinutes: 15)
let activeSnapshot = CycleSnapshot(configuration: currentConfig)

assertEqual(activeSnapshot.usageLimitMinutes, 20, "Active snapshot has 20 min limit")
assertEqual(activeSnapshot.restDurationMinutes, 15, "Active snapshot has 15 min rest")

// User changes settings mid-session to 40m / 20m
currentConfig.usageLimitMinutes = 40
currentConfig.restDurationMinutes = 20

// Active snapshot must remain untouched!
assertEqual(activeSnapshot.usageLimitMinutes, 20, "Active snapshot REMAINS 20 min limit after config change")
assertEqual(activeSnapshot.restDurationMinutes, 15, "Active snapshot REMAINS 15 min rest after config change")

// Next fresh cycle snapshot created from latest config
let nextSnapshot = CycleSnapshot(configuration: currentConfig)
assertEqual(nextSnapshot.usageLimitMinutes, 40, "Next snapshot adopts new 40 min limit")
assertEqual(nextSnapshot.restDurationMinutes, 20, "Next snapshot adopts new 20 min rest")
assertTrue(nextSnapshot.id != activeSnapshot.id, "Next snapshot has unique identity")

// 4. Deep Focus State Tests
print("\n[Suite 4: Deep Focus Session]")
let now = Date()
let activeSession = DeepFocusSession(startedAt: now, durationMinutes: 120)
assertTrue(activeSession.isActive, "Deep focus session is active when endsAt is in future")
assertEqual(activeSession.durationMinutes, 120, "Session duration is 120 minutes (2 hours)")

let pastDate = now.addingTimeInterval(-3600)
let expiredSession = DeepFocusSession(startedAt: pastDate, durationMinutes: 30)
assertFalse(expiredSession.isActive, "Deep focus session is inactive after end time passes")

print("\n=== TEST RESULTS SUMMARY ===")
print("Passed: \(passedCount), Failed: \(failedCount)")
if failedCount == 0 {
    print("ALL TESTS PASSED SUCCESSFULLY! 🚀")
} else {
    print("SOME TESTS FAILED.")
    exit(1)
}
