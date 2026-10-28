import Foundation

/// Read-only presentation; never schedules or changes restrictions.
enum BLTimePresentation {
    static func remaining(until end: Date, at now: Date) -> Int {
        max(0, Int(ceil(end.timeIntervalSince(now))))
    }

    static func remainingFraction(start: Date?, end: Date, at now: Date) -> Double? {
        guard let start, end > start else { return nil }
        return min(1, max(0, end.timeIntervalSince(now) / end.timeIntervalSince(start)))
    }

    static func label(seconds: Int) -> String {
        let value = max(0, seconds)
        if value >= 3600 {
            return String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
        }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
