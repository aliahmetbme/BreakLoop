//
//  DeviceActivityService.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import Foundation
import DeviceActivity
import FamilyControls

protocol DeviceActivityServiceProtocol {

    func startMonitoring(
        selection: FamilyActivitySelection,
        snapshot: CycleSnapshot
    ) throws

    func startMonitoring(
        selection: FamilyActivitySelection,
        configuration: CycleConfiguration
    ) throws

    func startMonitoring(
        selection: FamilyActivitySelection,
        limitMinutes: Int
    ) throws

    func startCooldown(
        durationMinutes: Int
    ) throws

    func startDeepFocus(
        durationMinutes: Int
    ) throws

    func stopDeepFocus()

    func stopMonitoring()
}

final class DeviceActivityService: DeviceActivityServiceProtocol {

    private let center = DeviceActivityCenter()

    static func makeDailySchedule() -> DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(
                hour: 0,
                minute: 0
            ),
            intervalEnd: DateComponents(
                hour: 23,
                minute: 59
            ),
            repeats: true
        )
    }

    static func checkpointStep(
        for limitMinutes: Int
    ) -> Int {
        CheckpointCalculator.checkpointStep(for: limitMinutes)
    }

    static func makeFocusEvents(
        selection: FamilyActivitySelection,
        limitMinutes: Int
    ) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        let step = checkpointStep(for: limitMinutes)
        var minute = step

        while minute < limitMinutes {
            events[
                DeviceActivityConstants.checkpointEvent(
                    minute: minute
                )
            ] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: [],
                threshold: DateComponents(
                    minute: minute
                ),
                includesPastActivity: false
            )

            minute += step
        }

        // Final usage limit
        events[
            DeviceActivityConstants.thresholdEvent
        ] = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: [],
            threshold: DateComponents(
                minute: limitMinutes
            ),
            includesPastActivity: false
        )

        return events
    }

    func startCooldown(
        durationMinutes: Int
    ) throws {

        let now = Date()

        guard let endDate = Calendar.current.date(
            byAdding: .minute,
            value: durationMinutes,
            to: now
        ) else {
            return
        }

        let startComponents = Calendar.current.dateComponents(
            [.hour, .minute, .second],
            from: now
        )

        let endComponents = Calendar.current.dateComponents(
            [.hour, .minute, .second],
            from: endDate
        )

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        try center.startMonitoring(
            DeviceActivityConstants.cooldownActivity,
            during: schedule
        )
    }

    func startDeepFocus(
        durationMinutes: Int
    ) throws {
        let now = Date()

        guard let endDate = Calendar.current.date(
            byAdding: .minute,
            value: durationMinutes,
            to: now
        ) else {
            return
        }

        let startComponents = Calendar.current.dateComponents(
            [.hour, .minute, .second],
            from: now
        )

        let endComponents = Calendar.current.dateComponents(
            [.hour, .minute, .second],
            from: endDate
        )

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        center.stopMonitoring([DeviceActivityConstants.deepFocusActivity])

        try center.startMonitoring(
            DeviceActivityConstants.deepFocusActivity,
            during: schedule
        )

        AppLogger.shared.info(
            "deep_focus_monitoring_started",
            message: "Deep Focus monitoring scheduled.",
            category: .monitoring,
            metadata: [
                "durationMinutes": "\(durationMinutes)",
                "endsAt": endDate.ISO8601Format()
            ]
        )
    }

    func stopDeepFocus() {
        center.stopMonitoring([DeviceActivityConstants.deepFocusActivity])
    }

    func stopMonitoring() {
        center.stopMonitoring([
            DeviceActivityConstants.focusActivity,
            DeviceActivityConstants.cooldownActivity,
            DeviceActivityConstants.deepFocusActivity
        ])
    }

    func startMonitoring(
        selection: FamilyActivitySelection,
        snapshot: CycleSnapshot
    ) throws {
        try startMonitoring(
            selection: selection,
            limitMinutes: snapshot.usageLimitMinutes
        )
    }

    func startMonitoring(
        selection: FamilyActivitySelection,
        configuration: CycleConfiguration
    ) throws {
        try startMonitoring(
            selection: selection,
            limitMinutes: configuration.usageLimitMinutes
        )
    }

    func startMonitoring(
        selection: FamilyActivitySelection,
        limitMinutes: Int
    ) throws {
        let schedule = Self.makeDailySchedule()
        let events = Self.makeFocusEvents(
            selection: selection,
            limitMinutes: limitMinutes
        )

        try center.startMonitoring(
            DeviceActivityConstants.focusActivity,
            during: schedule,
            events: events
        )

        AppLogger.shared.info(
            "focus_monitoring_started",
            message: "Initial focus monitoring started.",
            category: .monitoring,
            metadata: [
                "limitMinutes": "\(limitMinutes)",
                "checkpointCount": "\(events.count - 1)"
            ]
        )
    }
}
