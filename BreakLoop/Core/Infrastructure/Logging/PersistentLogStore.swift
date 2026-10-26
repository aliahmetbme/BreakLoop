//
//  PersistentLogStore.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 7.10.2026.
//

import Foundation

final class PersistentLogStore {

    private let storage: AppGroupStorage
    private let key = "breakloop.logs"
    private let maxLogCount = 300

    init(
        storage: AppGroupStorage = AppGroupStorage()
    ) {
        self.storage = storage
    }

    func append(_ entry: LogEntry) {
        var logs = loadLogs()

        logs.append(entry)

        if logs.count > maxLogCount {
            logs.removeFirst(
                logs.count - maxLogCount
            )
        }

        do {
            try storage.save(
                logs,
                forKey: key
            )
        } catch {
            // Persistent logger burada kendini tekrar loglamasın.
        }
    }

    func loadLogs() -> [LogEntry] {
        do {
            return try storage.load(
                [LogEntry].self,
                forKey: key
            ) ?? []
        } catch {
            return []
        }
    }

    func clear() {
        storage.remove(forKey: key)
    }
}
