import Foundation

func runTimePresentationTests() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    check(BLTimePresentation.remaining(until: now.addingTimeInterval(521.1), at: now) == 522,
          "Countdown rounds partial remaining seconds upward")
    check(BLTimePresentation.remaining(until: now, at: now) == 0, "Deadline equality displays finishing")
    check(BLTimePresentation.remaining(until: now.addingTimeInterval(-5), at: now) == 0, "Expired countdown never goes negative")
    check(BLTimePresentation.remainingFraction(start: nil, end: now.addingTimeInterval(900), at: now) == nil,
          "Cooldown without a start has no fabricated progress")
    check(BLTimePresentation.remainingFraction(start: now, end: now, at: now) == nil, "Zero-duration interval has no progress")
    check(BLTimePresentation.remainingFraction(start: now.addingTimeInterval(1), end: now, at: now) == nil,
          "Reversed interval has no progress")
    check(BLTimePresentation.remainingFraction(start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(1800), at: now) == 0.5,
          "Deep Focus progress derives from both real boundaries")
    check(BLTimePresentation.remainingFraction(start: now, end: now.addingTimeInterval(60), at: now.addingTimeInterval(-2)) == 1,
          "Before-start clock clamps progress to one")
    check(BLTimePresentation.remainingFraction(start: now.addingTimeInterval(-60), end: now, at: now.addingTimeInterval(2)) == 0,
          "Expired progress clamps to zero")
    check(BLTimePresentation.label(seconds: 522) == "08:42", "Countdown formats minute examples")
    check(BLTimePresentation.label(seconds: 18000) == "5:00:00", "Five-hour preset preserves hours")
    check(BLTimePresentation.label(seconds: -1) == "00:00", "Negative formatting is clamped")
    let extended = now.addingTimeInterval(522 + 900)
    check(BLTimePresentation.remaining(until: extended, at: now) == 1422,
          "Updated authoritative deadline immediately reflects extension")
    for (seconds, label) in [(86400,"24:00:00"),(18000,"5:00:00"),(7200,"2:00:00"),(3601,"1:00:01"),(3600,"1:00:00"),(3599,"59:59"),(3598,"59:58"),(600,"10:00"),(599,"09:59"),(60,"01:00"),(59,"00:59"),(10,"00:10"),(9,"00:09"),(1,"00:01"),(0,"00:00")] {
        check(BLTimePresentation.label(seconds: seconds) == label, "Stable-format boundary \(label)")
    }
}
