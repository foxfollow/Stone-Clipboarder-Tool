//
//  ErrorLogger.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 14.02.2026.
//

import Foundation
import os

/// Central logger — the app's only singleton.
///
/// Everything goes to the unified log (Console.app, subsystem = bundle id,
/// category = the `category` argument). `log` records errors and, when the
/// user enables "Save errors to log file", also appends them to a plaintext
/// file in Application Support. `debug` is for routine diagnostics and never
/// reaches the file.
///
/// Log metadata only (item type, counts, error descriptions) — never
/// clipboard content: the file is plaintext.
final class ErrorLogger {
    static let shared = ErrorLogger()

    /// UserDefaults key for the logging toggle
    static let enableFileLoggingKey = "enableErrorFileLogging"

    private static let subsystem = Bundle.main.bundleIdentifier ?? "StoneClipboarderTool"

    private let fileManager = FileManager.default
    private let logFileName = "StoneClipboarder_errors.log"
    private let maxLogFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    /// Serializes file access; `log` may be called from any thread.
    private let fileQueue = DispatchQueue(label: "StoneClipboarder.ErrorLogger", qos: .utility)
    /// Only used on `fileQueue`.
    private let timestampFormatter = ISO8601DateFormatter()

    var isFileLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enableFileLoggingKey)
    }

    private var logFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("StoneClipboarderTool")
        // Ensure directory exists
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent(logFileName)
    }

    private init() { /* Private initialization to ensure singleton usage */ }

    /// Log an error: unified log at `.error`, plus the log file when enabled.
    func log(_ message: String, category: String = "General", error: Error? = nil) {
        var line = "[\(category)] \(message)"
        if let error = error {
            line += " | Error: \(error.localizedDescription)"
        }

        Logger(subsystem: Self.subsystem, category: category).error("\(line, privacy: .public)")

        guard isFileLoggingEnabled else { return }
        let now = Date()
        fileQueue.async {
            self.writeToFile("[\(self.timestampFormatter.string(from: now))] \(line)")
        }
    }

    /// Routine diagnostics (not errors): unified log at `.debug` only, never the
    /// file. The message is only built when debug logging is enabled — see it
    /// with `log stream --level debug --predicate 'subsystem == "<bundle id>"'`.
    func debug(_ message: @autoclosure () -> String, category: String = "General") {
        let osLog = OSLog(subsystem: Self.subsystem, category: category)
        guard osLog.isEnabled(type: .debug) else { return }
        let text = message()
        Logger(osLog).debug("\(text, privacy: .public)")
    }

    private func writeToFile(_ line: String) {
        let url = logFileURL
        let lineWithNewline = line + "\n"

        do {
            if fileManager.fileExists(atPath: url.path) {
                // Check file size and rotate if needed
                let attrs = try fileManager.attributesOfItem(atPath: url.path)
                let fileSize = attrs[.size] as? UInt64 ?? 0
                if fileSize > maxLogFileSize {
                    rotateLogFile(at: url)
                }
            }

            if fileManager.fileExists(atPath: url.path) {
                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: url)
                defer { try? fileHandle.close() }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: Data(lineWithNewline.utf8))
            } else {
                // Create new file (also right after a rotation)
                try lineWithNewline.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // Can't log a logging failure to the file; the unified log still works.
            Logger(subsystem: Self.subsystem, category: "ErrorLogger")
                .error("Failed to write to log file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rotateLogFile(at url: URL) {
        let backupURL = url.deletingPathExtension().appendingPathExtension("old.log")
        try? fileManager.removeItem(at: backupURL)
        try? fileManager.moveItem(at: url, to: backupURL)
    }

    /// Returns the path to the log file (for display in settings)
    var logFilePath: String {
        logFileURL.path
    }

    /// Clears the log file
    func clearLog() {
        fileQueue.sync {
            try? fileManager.removeItem(at: logFileURL)
        }
    }

    /// Returns the log file size as a formatted string
    var logFileSizeString: String {
        guard fileManager.fileExists(atPath: logFileURL.path) else {
            return "No log file"
        }
        do {
            let attrs = try fileManager.attributesOfItem(atPath: logFileURL.path)
            let size = attrs[.size] as? Int64 ?? 0
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: size)
        } catch {
            return "Unknown"
        }
    }
}
