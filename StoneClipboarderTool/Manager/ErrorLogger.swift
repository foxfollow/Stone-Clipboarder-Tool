//
//  ErrorLogger.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 14.02.2026.
//

import Foundation

/// Centralized error logger that optionally writes errors to a .log file.
/// Logging to file is controlled by a UserDefaults toggle (disabled by default).
class ErrorLogger {
    static let shared = ErrorLogger()

    private let fileManager = FileManager.default
    private let logFileName = "StoneClipboarder_errors.log"
    private let maxLogFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB

    /// UserDefaults key for the logging toggle
    static let enableFileLoggingKey = "enableErrorFileLogging"

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

    private init() {}

    /// Log an error. Always prints to console. Writes to file if file logging is enabled.
    func log(_ message: String, category: String = "General", error: Error? = nil) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var logLine = "[\(timestamp)] [\(category)] \(message)"
        if let error = error {
            logLine += " | Error: \(error.localizedDescription)"
        }

        // Always print to console
        print(logLine)

        // Write to file if enabled
        guard isFileLoggingEnabled else { return }

        writeToFile(logLine)
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

                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: url)
                fileHandle.seekToEndOfFile()
                if let data = lineWithNewline.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                // Create new file
                try lineWithNewline.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // Silently fail — we can't log a logging failure
            print("ErrorLogger: Failed to write to log file: \(error)")
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
        try? fileManager.removeItem(at: logFileURL)
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
