//
//  UsageCycleCalculators.swift
//  BreakLoop
//

import Foundation

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

        return Result(
            wallClockSeconds: wallClockSeconds,
            activeUsageSeconds: activeUsageSeconds,
            estimatedRestSeconds: estimatedRestSeconds,
            isNaturalRest: estimatedRestSeconds >= requiredRestSeconds
        )
    }
}
