import Foundation
import OSLog
import AppKit

/// `LoggerService` writes through to Apple's `OSLog` persistence so messages show
/// up in Console.app under `subsystem: com.textractor.app`.
public final class LoggerService {
    public static let shared = LoggerService()

    public let subsystem = "com.textractor.app"
    public let category = "Textractor"

    public let osLogger: Logger

    private init() {
        osLogger = Logger(subsystem: subsystem, category: category)
    }

    // MARK: - Convenience

    public func info(_ message: String, file: String = #fileID, line: Int = #line) {
        osLogger.info("\(file, privacy: .public):\(line, privacy: .public) — \(message, privacy: .public)")
    }

    public func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
    }

    public func error(_ message: String, error: Error? = nil) {
        if let error {
            osLogger.error("\(message, privacy: .public) (\(error.localizedDescription, privacy: .public))")
        } else {
            osLogger.error("\(message, privacy: .public)")
        }
    }

    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
    }
}
