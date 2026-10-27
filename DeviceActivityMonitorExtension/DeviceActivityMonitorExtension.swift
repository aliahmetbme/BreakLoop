//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//
import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let store = BreakLoopManagedSettings.makeStore()
    private let center = DeviceActivityCenter()
    private let storage = AppGroupStorage()

    override func intervalDidStart(
        for activity: DeviceActivityName
    ) {
        super.intervalDidStart(for: activity)

        AppLogger.shared.info(
            "interval_started",
            message: "DeviceActivity interval started.",
            category: .monitoring,
            metadata: [
                "activity": activity.rawValue
            ]
        )
    }

    override func intervalDidEnd(
        for activity: DeviceActivityName
    ) {
        super.intervalDidEnd(for: activity)

        AppLogger.shared.info(
            "interval_ended",
            message: "DeviceActivity interval ended.",
            category: .monitoring,
            metadata: [
                "activity": activity.rawValue
            ]
        )

        if activity == DeviceActivityConstants.deepFocusActivity {
            removeShield()
            storage.clearDeepFocusSession()

            AppLogger.shared.info(
                "deep_focus_ended",
                message: "Deep Focus session completed and shield removed.",
                category: .monitoring
            )

            if storage.isBreakLoopActive() {
                let config = storage.loadCycleConfiguration()
                let snapshot = AppGroupStorage.CycleSnapshot(configuration: config)
                try? storage.saveActiveCycleSnapshot(snapshot)
                storage.clearUsageCheckpointState()
                startFreshCycle(snapshot: snapshot)
            }
            return
        }

        guard activity == DeviceActivityConstants.cooldownActivity else {
            return
        }

        guard let cooldownEndDate = try? storage.loadCooldownEndDate() else {
            AppLogger.shared.warning(
                "cooldown_end_date_missing",
                message: "Cooldown end date could not be loaded.",
                category: .cooldown
            )
            return
        }

        let now = Date()

        if now.addingTimeInterval(2) < cooldownEndDate {
            AppLogger.shared.warning(
                "cooldown_early_end_ignored",
                message: "Cooldown interval ended too early, ignoring callback.",
                category: .cooldown,
                metadata: [
                    "now": now.ISO8601Format(),
                    "expectedEnd": cooldownEndDate.ISO8601Format()
                ]
            )

            return
        }

        removeShield()
        storage.clearCooldownEndDate()
        storage.clearUsageCheckpointState()

        AppLogger.shared.info(
            "cooldown_finished",
            message: "Cooldown finished, shield removed, and stale checkpoint cleared.",
            category: .cooldown
        )

        let config = storage.loadCycleConfiguration()
        let newSnapshot = AppGroupStorage.CycleSnapshot(configuration: config)
        try? storage.saveActiveCycleSnapshot(newSnapshot)
        startFreshCycle(snapshot: newSnapshot)
    }

    override func intervalWillStartWarning(
        for activity: DeviceActivityName
    ) {
        super.intervalWillStartWarning(for: activity)

        AppLogger.shared.debug(
            "interval_start_warning",
            message: "DeviceActivity interval will start soon.",
            category: .monitoring,
            metadata: [
                "activity": activity.rawValue
            ]
        )
    }

    override func intervalWillEndWarning(
        for activity: DeviceActivityName
    ) {
        super.intervalWillEndWarning(for: activity)

        AppLogger.shared.debug(
            "interval_end_warning",
            message: "DeviceActivity interval will end soon.",
            category: .monitoring,
            metadata: [
                "activity": activity.rawValue
            ]
        )
    }

    override func eventWillReachThresholdWarning(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventWillReachThresholdWarning(
            event,
            activity: activity
        )

        AppLogger.shared.debug(
            "threshold_warning",
            message: "Usage threshold will be reached soon.",
            category: .threshold,
            metadata: [
                "activity": activity.rawValue,
                "event": event.rawValue
            ]
        )
    }

    private func applyShield(
        to selection: FamilyActivitySelection
    ) {
        store.shield.applications =
            selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens

        store.shield.applicationCategories =
            selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)

        AppLogger.shared.info(
            "shield_applied",
            message: "Shield was applied to the selected activities.",
            category: .shield,
            metadata: [
                "applicationCount":
                    "\(selection.applicationTokens.count)",
                "categoryCount":
                    "\(selection.categoryTokens.count)"
            ]
        )
    }

    private func removeShield() {
        store.clearAllSettings()

        AppLogger.shared.info(
            "shield_removed",
            message: "Managed Settings shield was removed.",
            category: .shield
        )
    }

    private func startCooldown(
        minutes: Int
    ) {
        let minimumCooldownMinutes = 15
        let safeMinutes = max(minutes, minimumCooldownMinutes)

        let calendar = Calendar.current
        let now = Date()

        guard let endDate = calendar.date(
            byAdding: .minute,
            value: safeMinutes,
            to: now
        ) else {
            AppLogger.shared.error(
                "cooldown_end_date_failed",
                message: "Could not calculate cooldown end date.",
                category: .cooldown,
                metadata: [
                    "requestedMinutes": "\(minutes)"
                ]
            )

            return
        }
        
        let storage = AppGroupStorage()

        do {
            try storage.saveCooldownEndDate(endDate)
        } catch {
            AppLogger.shared.error(
                "cooldown_end_date_save_failed",
                message: error.localizedDescription,
                category: .storage
            )
        }

        let startComponents = calendar.dateComponents(
            [
                .year,
                .month,
                .day,
                .hour,
                .minute,
                .second
            ],
            from: now
        )

        let endComponents = calendar.dateComponents(
            [
                .year,
                .month,
                .day,
                .hour,
                .minute,
                .second
            ],
            from: endDate
        )

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        center.stopMonitoring([
            DeviceActivityConstants.cooldownActivity
        ])

        AppLogger.shared.info(
            "cooldown_schedule_created",
            message: "Cooldown schedule was created.",
            category: .cooldown,
            metadata: [
                "durationMinutes": "\(safeMinutes)",
                "now": now.ISO8601Format(),
                "requestedEnd": endDate.ISO8601Format()
            ]
        )

        do {
            try center.startMonitoring(
                DeviceActivityConstants.cooldownActivity,
                during: schedule
            )

            var metadata: [String: String] = [
                "durationMinutes": "\(safeMinutes)",
                "startedAt": now.ISO8601Format(),
                "scheduledEndAt": endDate.ISO8601Format()
            ]

            // Apple'ın schedule'ı gerçekte nasıl yorumladığını görelim.
            if let nextInterval = schedule.nextInterval {
                metadata["actualIntervalStart"] =
                    nextInterval.start.ISO8601Format()

                metadata["actualIntervalEnd"] =
                    nextInterval.end.ISO8601Format()

                metadata["actualDurationSeconds"] =
                    "\(nextInterval.duration)"
            }

            AppLogger.shared.info(
                "cooldown_started",
                message: "Cooldown monitoring started successfully.",
                category: .cooldown,
                metadata: metadata
            )

        } catch {
            AppLogger.shared.error(
                "cooldown_failed",
                message: String(describing: error),
                category: .cooldown,
                metadata: [
                    "durationMinutes": "\(safeMinutes)",
                    "start": now.ISO8601Format(),
                    "end": endDate.ISO8601Format()
                ]
            )
        }
    }
    
    private func startFreshCycle(
        snapshot: AppGroupStorage.CycleSnapshot
    ) {
        guard let selection = try? storage.loadActivitySelection() else {
            AppLogger.shared.error(
                "focus_restart_selection_failed",
                message: "Could not load selection while starting fresh cycle.",
                category: .storage
            )
            return
        }

        let schedule = DeviceActivityService.makeDailySchedule()
        let events = DeviceActivityService.makeFocusEvents(
            selection: selection,
            limitMinutes: snapshot.usageLimitMinutes
        )

        do {
            try center.startMonitoring(
                DeviceActivityConstants.focusActivity,
                during: schedule,
                events: events
            )

            AppLogger.shared.info(
                "focus_monitoring_restarted",
                message: "Focus monitoring started for a fresh cycle.",
                category: .monitoring,
                metadata: [
                    "limitMinutes": "\(snapshot.usageLimitMinutes)",
                    "checkpointCount": "\(events.count - 1)",
                    "snapshotId": snapshot.id.uuidString
                ]
            )

        } catch {
            AppLogger.shared.error(
                "focus_monitoring_restart_failed",
                message: String(describing: error),
                category: .monitoring,
                metadata: [
                    "limitMinutes": "\(snapshot.usageLimitMinutes)"
                ]
            )
        }
    }
    
    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(
            event,
            activity: activity
        )

        guard
            activity == DeviceActivityConstants.focusActivity
        else {
            return
        }

        // Ara checkpoint.
        if let checkpointMinute =
            DeviceActivityConstants.checkpointMinute(
                from: event
            ) {

            handleUsageCheckpoint(
                usageMinute: checkpointMinute
            )

            return
        }

        // Final kullanım limiti.
        guard
            event == DeviceActivityConstants.thresholdEvent
        else {
            return
        }

        handleFinalThreshold()
    }

    private func handleUsageCheckpoint(
        usageMinute: Int
    ) {
        AppLogger.shared.info(
            "usage_checkpoint",
            message: "Checkpoint reached at usage minute \(usageMinute).",
            category: .session,
            metadata: [
                "usageMinute": "\(usageMinute)"
            ]
        )

        let snapshot = storage.loadActiveCycleSnapshot()
            ?? AppGroupStorage.CycleSnapshot(configuration: storage.loadCycleConfiguration())

        if evaluateNaturalRest(
            currentUsageMinute: usageMinute,
            restDurationMinutes: snapshot.restDurationMinutes
        ) {
            storage.clearUsageCheckpointState()

            // Yeni döngü için en güncel ayarlardan taze snapshot oluştur
            let latestConfig = storage.loadCycleConfiguration()
            let newSnapshot = AppGroupStorage.CycleSnapshot(configuration: latestConfig)
            try? storage.saveActiveCycleSnapshot(newSnapshot)

            startFreshCycle(snapshot: newSnapshot)
        }
    }

    private func handleFinalThreshold() {
        AppLogger.shared.info(
            "threshold_reached",
            message: "Final usage threshold reached.",
            category: .threshold
        )

        let snapshot = storage.loadActiveCycleSnapshot()
            ?? AppGroupStorage.CycleSnapshot(configuration: storage.loadCycleConfiguration())

        if evaluateNaturalRest(
            currentUsageMinute: snapshot.usageLimitMinutes,
            restDurationMinutes: snapshot.restDurationMinutes
        ) {
            storage.clearUsageCheckpointState()

            // Doğal mola ile yeni döngüye geçiş
            let latestConfig = storage.loadCycleConfiguration()
            let newSnapshot = AppGroupStorage.CycleSnapshot(configuration: latestConfig)
            try? storage.saveActiveCycleSnapshot(newSnapshot)

            startFreshCycle(snapshot: newSnapshot)
            return
        }

        guard
            let selection =
                try? storage.loadActivitySelection()
        else {
            AppLogger.shared.error(
                "selection_missing",
                message: "Cannot apply shield because activity selection could not be loaded.",
                category: .shield
            )
            return
        }

        applyShield(to: selection)
        storage.clearUsageCheckpointState()
        startCooldown(minutes: snapshot.restDurationMinutes)
    }

    private func evaluateNaturalRest(
        currentUsageMinute: Int,
        restDurationMinutes: Int
    ) -> Bool {
        let now = Date()

        guard
            let previous =
                try? storage.loadUsageCheckpointState()
        else {
            saveCheckpoint(
                minute: currentUsageMinute,
                timestamp: now
            )

            return false
        }

        let result = NaturalRestCalculator.calculate(
            currentUsageMinute: currentUsageMinute,
            currentTimestamp: now,
            previousUsageMinute: previous.usageMinute,
            previousTimestamp: previous.timestamp,
            requiredRestMinutes: restDurationMinutes
        )

        AppLogger.shared.info(
            "natural_rest_calculated",
            message: "Estimated rest duration calculated.",
            category: .session,
            metadata: [
                "previousUsageMinute":
                    "\(previous.usageMinute)",
                "currentUsageMinute":
                    "\(currentUsageMinute)",
                "wallClockSeconds":
                    "\(result.wallClockSeconds)",
                "activeUsageSeconds":
                    "\(result.activeUsageSeconds)",
                "estimatedRestSeconds":
                    "\(result.estimatedRestSeconds)",
                "requiredRestSeconds":
                    "\(restDurationMinutes * 60)"
            ]
        )

        if result.isNaturalRest {
            AppLogger.shared.info(
                "natural_rest_detected",
                message: "Natural rest detected. Fresh cycle will start without shield.",
                category: .session,
                metadata: [
                    "estimatedRestSeconds":
                        "\(result.estimatedRestSeconds)",
                    "requiredRestSeconds":
                        "\(restDurationMinutes * 60)"
                ]
            )

            return true
        }

        saveCheckpoint(
            minute: currentUsageMinute,
            timestamp: now
        )

        return false
    }

    private func saveCheckpoint(
        minute: Int,
        timestamp: Date = Date()
    ) {
        try? storage.saveUsageCheckpointState(
            AppGroupStorage.UsageCheckpointState(
                usageMinute: minute,
                timestamp: timestamp
            )
        )
    }
}

