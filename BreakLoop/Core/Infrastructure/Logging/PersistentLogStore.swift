//
//  PersistentLogStore.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 7.10.2026.
//

import Foundation

final class PersistentLogStore {

    static let shared = PersistentLogStore()

    private let fileManager = FileManager.default
    private let appGroupName = AppGroupStorage.suiteName
    private let logFileName = "breakloop.jsonl"
    private let rotatedFileName = "breakloop.old.jsonl"
    private let legacyUserDefaultsKey = "breakloop.logs"
    private let maxFileSizeBytes: Int64 = 256 * 1024 // 256 KB max active file size (~512 KB max total)

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var containerDirectoryURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private var currentFileURL: URL? {
        containerDirectoryURL?.appendingPathComponent(logFileName)
    }

    private var rotatedFileURL: URL? {
        containerDirectoryURL?.appendingPathComponent(rotatedFileName)
    }

    init() {
        // Clean up legacy full-array logs from UserDefaults to free up memory and disk
        UserDefaults(suiteName: appGroupName)?.removeObject(forKey: legacyUserDefaultsKey)
    }

    func append(_ entry: LogEntry) {
        guard let currentFileURL = currentFileURL else { return }

        do {
            // Encode ONLY the single entry to JSON lines
            var lineData = try encoder.encode(entry)
            lineData.append(0x0A) // newline '\n'

            // Check if rotation is needed before appending
            rotateIfExceedsLimit(currentFileURL: currentFileURL)

            let path = currentFileURL.path
            if !fileManager.fileExists(atPath: path) {
                fileManager.createFile(atPath: path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: currentFileURL) else { return }
            defer {
                try? handle.close()
            }

            let fd = handle.fileDescriptor
            flock(fd, LOCK_EX)
            defer {
                flock(fd, LOCK_UN)
            }

            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
        } catch {
            // Best-effort: logging failure must NEVER crash or affect Screen Time enforcement
        }
    }

    private func rotateIfExceedsLimit(currentFileURL: URL) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: currentFileURL.path),
              let size = attributes[.size] as? Int64,
              size >= maxFileSizeBytes else {
            return
        }

        if let rotatedFileURL = rotatedFileURL {
            try? fileManager.removeItem(at: rotatedFileURL)
            try? fileManager.moveItem(at: currentFileURL, to: rotatedFileURL)
        } else {
            try? fileManager.removeItem(at: currentFileURL)
        }
    }

    func loadRecent(limit: Int = 100) -> [LogEntry] {
        guard limit > 0 else { return [] }

        var entries: [LogEntry] = []

        // Read from current file first
        if let currentFileURL = currentFileURL,
           fileManager.fileExists(atPath: currentFileURL.path) {
            entries.append(contentsOf: readEntries(from: currentFileURL))
        }

        // If fewer than requested and a rotated file exists, prepend older entries
        if entries.count < limit,
           let rotatedFileURL = rotatedFileURL,
           fileManager.fileExists(atPath: rotatedFileURL.path) {
            let olderEntries = readEntries(from: rotatedFileURL)
            entries.insert(contentsOf: olderEntries, at: 0)
        }

        if entries.count > limit {
            return Array(entries.suffix(limit))
        }

        return entries
    }

    func loadLogs() -> [LogEntry] {
        loadRecent(limit: 300)
    }

    func clear() {
        if let currentFileURL = currentFileURL {
            try? fileManager.removeItem(at: currentFileURL)
        }
        if let rotatedFileURL = rotatedFileURL {
            try? fileManager.removeItem(at: rotatedFileURL)
        }
        UserDefaults(suiteName: appGroupName)?.removeObject(forKey: legacyUserDefaultsKey)
    }

    private func readEntries(from fileURL: URL) -> [LogEntry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        var results: [LogEntry] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8) else {
                continue
            }
            if let entry = try? decoder.decode(LogEntry.self, from: lineData) {
                results.append(entry)
            }
        }
        return results
    }
}
