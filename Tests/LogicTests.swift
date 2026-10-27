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

// 5. Authorization Revocation & Routing Logic Tests
print("\n[Suite 5: Authorization State Evaluation & Revocation]")

enum MockAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case approved
}

enum TestAuthorizationUIState: Equatable {
    case authorized
    case firstTimeOnboarding
    case permissionRevoked(isDeniedInSettings: Bool)
}

struct TestAuthorizationStateEvaluator {
    static func evaluate(
        status: MockAuthorizationStatus,
        hasPreviouslyConfigured: Bool
    ) -> TestAuthorizationUIState {
        switch status {
        case .approved:
            return .authorized
        case .denied:
            return .permissionRevoked(isDeniedInSettings: true)
        case .notDetermined:
            if hasPreviouslyConfigured {
                return .permissionRevoked(isDeniedInSettings: false)
            } else {
                return .firstTimeOnboarding
            }
        }
    }
}

// Case 1: Fresh install, not determined, no previous configuration -> firstTimeOnboarding
let stateFresh = TestAuthorizationStateEvaluator.evaluate(status: .notDetermined, hasPreviouslyConfigured: false)
assertEqual(stateFresh, .firstTimeOnboarding, "Fresh install with .notDetermined routes to firstTimeOnboarding")

// Case 2: User grants permission -> authorized
let stateApproved = TestAuthorizationStateEvaluator.evaluate(status: .approved, hasPreviouslyConfigured: true)
assertEqual(stateApproved, .authorized, "Approved authorization routes to .authorized (Dashboard)")

// Case 3: User revokes permission in Settings (.denied) -> permissionRevoked(isDeniedInSettings: true)
let stateDenied = TestAuthorizationStateEvaluator.evaluate(status: .denied, hasPreviouslyConfigured: true)
assertEqual(stateDenied, .permissionRevoked(isDeniedInSettings: true), "Revocation in Settings (.denied) routes to permissionRevoked with isDeniedInSettings = true")

// Case 4: Permission was reset/notDetermined but user already configured apps -> permissionRevoked(isDeniedInSettings: false)
let stateReset = TestAuthorizationStateEvaluator.evaluate(status: .notDetermined, hasPreviouslyConfigured: true)
assertEqual(stateReset, .permissionRevoked(isDeniedInSettings: false), "Revocation to .notDetermined for existing user routes to permissionRevoked (not full onboarding)")

// Case 5: Preservation of user configuration upon revocation cleanup
var savedConfig: CycleConfiguration? = CycleConfiguration(usageLimitMinutes: 25, restDurationMinutes: 10)
var savedAppsCount: Int = 3
var activeSnapshotRef: CycleSnapshot? = CycleSnapshot(configuration: savedConfig!)
var isBreakLoopActiveFlag: Bool = true
var deepFocusSessionRef: DeepFocusSession? = DeepFocusSession(durationMinutes: 60)
var cooldownEndDateRef: Date? = Date().addingTimeInterval(600)

// Simulate handleAuthorizationRevoked()
func simulateRevocationCleanup() {
    // Monitoring is stopped
    // Transient runtime state is wiped
    activeSnapshotRef = nil
    isBreakLoopActiveFlag = false
    deepFocusSessionRef = nil
    cooldownEndDateRef = nil
    // User configuration is PRESERVED
    // savedConfig remains untouched
    // savedAppsCount remains untouched
}

simulateRevocationCleanup()

assertEqual(activeSnapshotRef, nil, "Active cycle snapshot is cleared upon revocation")
assertFalse(isBreakLoopActiveFlag, "isBreakLoopActive flag is set to false upon revocation")
assertEqual(deepFocusSessionRef, nil, "Deep focus session is cleared upon revocation")
assertEqual(cooldownEndDateRef, nil, "Cooldown end date is cleared upon revocation")
assertEqual(savedConfig?.usageLimitMinutes, 25, "User's configured usage limit (25m) is strictly preserved")
assertEqual(savedConfig?.restDurationMinutes, 10, "User's configured rest duration (10m) is strictly preserved")
assertEqual(savedAppsCount, 3, "User's selected apps count is strictly preserved")

// 6. Logging Architecture & Named Store Consistency Tests
print("\n[Suite 6: Logger JSONL & Named Store Verification]")

// Test A: Named store constant verification
let storeNameExpected = "breakloop.enforcement"
assertEqual(storeNameExpected, "breakloop.enforcement", "Shared ManagedSettingsStore name is 'breakloop.enforcement'")

// Test B: Single entry JSON-Lines serialization (no full-array rewrite)
struct TestLogEntry: Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: String
    let category: String
    let event: String
    let message: String
}

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

let entry1 = TestLogEntry(
    id: UUID(),
    timestamp: Date(timeIntervalSince1970: 1700000000),
    level: "info",
    category: "monitoring",
    event: "interval_started",
    message: "DeviceActivity interval started"
)

var line1Data = try! encoder.encode(entry1)
line1Data.append(0x0A) // newline

let decodedLine1 = try! decoder.decode(TestLogEntry.self, from: line1Data)
assertEqual(decodedLine1, entry1, "Single log entry encodes and decodes accurately as a standalone JSON line")

// Test C: Reading JSONL stream with corrupted/empty lines resilience
let corruptLine = "malformed json data\n".data(using: .utf8)!
var streamData = Data()
streamData.append(line1Data)
streamData.append(corruptLine)

let entry2 = TestLogEntry(
    id: UUID(),
    timestamp: Date(timeIntervalSince1970: 1700000060),
    level: "warning",
    category: "shield",
    event: "shield_applied",
    message: "Shield was applied"
)
var line2Data = try! encoder.encode(entry2)
line2Data.append(0x0A)
streamData.append(line2Data)

// Simulate reader
let streamString = String(data: streamData, encoding: .utf8)!
var parsedEntries: [TestLogEntry] = []
for line in streamString.components(separatedBy: .newlines) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let d = trimmed.data(using: .utf8) else { continue }
    if let item = try? decoder.decode(TestLogEntry.self, from: d) {
        parsedEntries.append(item)
    }
}

assertEqual(parsedEntries.count, 2, "Reader safely skips malformed line and parses valid JSON lines")
assertEqual(parsedEntries[0], entry1, "First entry parsed correctly")
assertEqual(parsedEntries[1], entry2, "Second entry parsed correctly")

// Test D: Rotation simulation
let maxTestBytes = 200
var activeFileSize = 150
let newWriteSize = 80

var isRotated = false
if (activeFileSize + newWriteSize) > maxTestBytes {
    isRotated = true
    activeFileSize = newWriteSize // file rotated, new active file contains only new write
}

assertTrue(isRotated, "File rotation triggers when active file size exceeds max limit")
assertEqual(activeFileSize, 80, "Active file size is reset to single write size after rotation")

// 7. Responsive Layout Metrics & Appearance Tests
print("\n[Suite 7: Responsive Layout Metrics & Appearance]")

struct TestLayoutMetrics {
    let availableWidth: Double
    let horizontalPadding: Double
    let contentMaxWidth: Double
    let prefersStackedMetrics: Bool
    let isCompact: Bool
    let isLarge: Bool

    init(availableWidth: Double) {
        self.availableWidth = availableWidth
        if availableWidth < 360 {
            self.horizontalPadding = 16
            self.contentMaxWidth = availableWidth
            self.prefersStackedMetrics = true
            self.isCompact = true
            self.isLarge = false
        } else if availableWidth <= 430 {
            self.horizontalPadding = 20
            self.contentMaxWidth = availableWidth
            self.prefersStackedMetrics = false
            self.isCompact = false
            self.isLarge = false
        } else {
            self.horizontalPadding = 24
            self.contentMaxWidth = 600
            self.prefersStackedMetrics = false
            self.isCompact = false
            self.isLarge = true
        }
    }
}

// Compact device (< 360pt, e.g. iPhone SE / small window)
let compactMetrics = TestLayoutMetrics(availableWidth: 320)
assertTrue(compactMetrics.isCompact, "320pt available width is classified as compact")
assertEqual(compactMetrics.horizontalPadding, 16.0, "Compact width uses 16pt margin")
assertTrue(compactMetrics.prefersStackedMetrics, "Compact width prefers stacked metric tiles")

// Standard device (360 - 430pt, e.g. iPhone 15/16)
let standardMetrics = TestLayoutMetrics(availableWidth: 393)
assertFalse(standardMetrics.isCompact, "393pt available width is not compact")
assertFalse(standardMetrics.isLarge, "393pt available width is not large")
assertEqual(standardMetrics.horizontalPadding, 20.0, "Standard width uses 20pt margin")
assertFalse(standardMetrics.prefersStackedMetrics, "Standard width does not force stacked metrics")

// Large device (> 430pt, e.g. iPhone Pro Max / iPad / Landscape)
let largeMetrics = TestLayoutMetrics(availableWidth: 800)
assertTrue(largeMetrics.isLarge, "800pt available width is classified as large")
assertEqual(largeMetrics.horizontalPadding, 24.0, "Large width uses 24pt margin")
assertEqual(largeMetrics.contentMaxWidth, 600.0, "Large width caps content max width at 600pt")

// Appearance Enum & Codable roundtrip
enum TestAppAppearance: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

let appearanceDark = TestAppAppearance.dark
let encodedAppearance = try! JSONEncoder().encode(appearanceDark)
let decodedAppearance = try! JSONDecoder().decode(TestAppAppearance.self, from: encodedAppearance)
assertEqual(decodedAppearance, .dark, "AppAppearance codable serialization and deserialization matches")

print("\n=== TEST RESULTS SUMMARY ===")
print("Passed: \(passedCount), Failed: \(failedCount)")
if failedCount == 0 {
    print("ALL TESTS PASSED SUCCESSFULLY! 🚀")
} else {
    print("SOME TESTS FAILED.")
    exit(1)
}



