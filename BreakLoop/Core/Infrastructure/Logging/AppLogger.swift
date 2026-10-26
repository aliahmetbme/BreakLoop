//
//  AppLogger.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 7.10.2026.
//

import Foundation
import OSLog

final class AppLogger {

    static let shared = AppLogger()

    private let subsystem =
        "com.aliahmeterdogdu.BreakLoop"

    private let persistentStore =
        PersistentLogStore()

    private init() {}

    func debug(
        _ event: String,
        message: String,
        category: LogCategory,
        metadata: [String: String] = [:]
    ) {
        log(
            level: .debug,
            event: event,
            message: message,
            category: category,
            metadata: metadata
        )
    }

    func info(
        _ event: String,
        message: String,
        category: LogCategory,
        metadata: [String: String] = [:]
    ) {
        log(
            level: .info,
            event: event,
            message: message,
            category: category,
            metadata: metadata
        )
    }

    func warning(
        _ event: String,
        message: String,
        category: LogCategory,
        metadata: [String: String] = [:]
    ) {
        log(
            level: .warning,
            event: event,
            message: message,
            category: category,
            metadata: metadata
        )
    }

    func error(
        _ event: String,
        message: String,
        category: LogCategory,
        metadata: [String: String] = [:]
    ) {
        log(
            level: .error,
            event: event,
            message: message,
            category: category,
            metadata: metadata
        )
    }

    private func log(
        level: LogLevel,
        event: String,
        message: String,
        category: LogCategory,
        metadata: [String: String]
    ) {

        let logger = Logger(
            subsystem: subsystem,
            category: category.rawValue
        )

        let formattedMessage =
            "[BL] [\(event)] \(message)"

        switch level {
        case .debug:
            logger.debug(
                "\(formattedMessage, privacy: .public)"
            )

        case .info:
            logger.info(
                "\(formattedMessage, privacy: .public)"
            )

        case .warning:
            logger.warning(
                "\(formattedMessage, privacy: .public)"
            )

        case .error:
            logger.error(
                "\(formattedMessage, privacy: .public)"
            )
        }

        let entry = LogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            category: category,
            event: event,
            message: message,
            metadata: metadata
        )

        persistentStore.append(entry)
    }
}
