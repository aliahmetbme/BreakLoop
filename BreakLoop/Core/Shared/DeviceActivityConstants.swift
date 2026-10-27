//
//  DeviceActivityConstants.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 7.10.2026.
//

import Foundation
import DeviceActivity
import ManagedSettings

enum DeviceActivityConstants {
    static let focusActivity =
        DeviceActivityName("breakloop.focus")

    static let thresholdEvent =
        DeviceActivityEvent.Name("breakloop.threshold")

    static let cooldownActivity =
        DeviceActivityName("breakloop.cooldown")

    static let deepFocusActivity =
        DeviceActivityName("breakloop.deepFocus")

    static let checkpointPrefix =
        "breakloop.checkpoint."

    static func checkpointEvent(
        minute: Int
    ) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name(
            "\(checkpointPrefix)\(minute)"
        )
    }

    static func checkpointMinute(
        from event: DeviceActivityEvent.Name
    ) -> Int? {
        guard event.rawValue.hasPrefix(checkpointPrefix) else {
            return nil
        }

        let value = event.rawValue
            .replacingOccurrences(
                of: checkpointPrefix,
                with: ""
            )

        return Int(value)
    }
}

enum BreakLoopManagedSettings {
    static let storeName =
        ManagedSettingsStore.Name("breakloop.enforcement")

    static func makeStore() -> ManagedSettingsStore {
        ManagedSettingsStore(named: storeName)
    }
}
