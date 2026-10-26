//
//  LogCatagory.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 7.10.2026.
//

import Foundation

enum LogLevel: String, Codable {
    case debug
    case info
    case warning
    case error
}

enum LogCategory: String, Codable {
    case authorization
    case selection
    case monitoring
    case threshold
    case cooldown
    case shield
    case session
    case storage
    case lifecycle
}

struct LogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let event: String
    let message: String
    let metadata: [String: String]
}
