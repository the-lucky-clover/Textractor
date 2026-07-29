import Foundation
import OSLog
import AppKit

/// `LoggerService` writes through to Apple's `OSLog` persistence so messages show
/// up in Console.app under `subsystem: com.textractor.app`.
/// Optionally also writes to a local log file for extended debugging.
public final class LoggerService {
    public static let shared = LoggerService()

    public let subsystem = "com.textractor.app"
    public let category = "Textractor"

    public let osLogger: Logger

    /// File-based logging (enabled via settings).
    private var logFileHandle: FileHandle?
    private let logQueue = DispatchQueue(label: "com.textractor.logger.file", qos: .utility)
    private var isFileLoggingEnabled = false

    private init() {
        osLogger = Logger(subsystem: subsystem, category: category)
    }

    /// Enable/disable file-based logging. Thread-safe.
    public func setFileLoggingEnabled(_ enabled: Bool) {
        logQueue.async {
            if enabled && self.logFileHandle == nil {
                self.openLogFile()
            } else if !enabled && self.logFileHandle != nil {
                self.closeLogFile()
            }
            self.isFileLoggingEnabled = enabled
        }
    }

    /// Returns the path to the log file if file logging is active.
    public var logFilePath: String? {
        logQueue.sync {
            guard self.logFileHandle != nil else { return nil }
            return self.currentLogFileURL()?.path
        }
    }

    /// Opens (or creates) the log file in the app's cache directory.
    private func openLogFile() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let logDir = cacheDir.appendingPathComponent("Textractor/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let logURL = logDir.appendingPathComponent("textractor-\(timestamp).log")
        do {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            logFileHandle = try FileHandle(forWritingTo: logURL)
            logFileHandle?.seekToEndOfFile()
            writeToFile("[Textractor] Log file opened at \(Date())\n")
        } catch {
            osLogger.error("Failed to open log file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func closeLogFile() {
        writeToFile("[Textractor] Log file closed at \(Date())\n")
        logFileHandle?.closeFile()
        logFileHandle = nil
    }

    private func currentLogFileURL() -> URL? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let logDir = cacheDir.appendingPathComponent("Textractor/Logs", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        let dated = files.compactMap { url -> (URL, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                  let date = values.creationDate else { return nil }
            return (url, date)
        }
        return dated.sorted { $0.1 > $1.1 }.first?.0
    }

    /// Open the log folder in Finder.
    public func openLogFolder() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let logDir = cacheDir.appendingPathComponent("Textractor/Logs", isDirectory: true)
        NSWorkspace.shared.open(logDir)
    }

    // MARK: - Convenience

    public func info(_ message: String, file: String = #fileID, line: Int = #line) {
        osLogger.info("\(file, privacy: .public):\(line, privacy: .public) — \(message, privacy: .private)")
        writeToFile("[INFO] \(timestamp()) \(file):\(line) — \(message)")
    }

    public func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .private)")
        writeToFile("[WARN] \(timestamp()) \(message)")
    }

    public func error(_ message: String, error: Error? = nil) {
        if let error {
            osLogger.error("\(message, privacy: .private) (\(error.localizedDescription, privacy: .private))")
            writeToFile("[ERROR] \(timestamp()) \(message) (\(error.localizedDescription))")
        } else {
            osLogger.error("\(message, privacy: .private)")
            writeToFile("[ERROR] \(timestamp()) \(message)")
        }
    }

    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .private)")
        writeToFile("[DEBUG] \(timestamp()) \(message)")
    }

    // MARK: - File writing

    private func writeToFile(_ message: String) {
        guard isFileLoggingEnabled, let handle = logFileHandle else { return }
        let line = "\(message)\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
