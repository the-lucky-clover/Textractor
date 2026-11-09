import Foundation

/// `TelemetryService` persists every event as JSONL to the local disk
/// (`~/Library/Application Support/Textractor/telemetry.jsonl`).
/// It is **never** transmitted off-device. Privacy-first by construction.
public final class TelemetryService {
    public static let shared = TelemetryService()

    public let fileURL: URL

    /// Single source of truth for the user's opt-in, mirrored from
    /// `AppSettings.localTelemetryEnabled` by `SettingsStore`. Low-level
    /// services read this instead of hardcoding `true`, so disabling telemetry
    /// in Settings actually stops all local logging.
    private let enabledLock = NSLock()
    private var enabled = false
    public var isEnabled: Bool {
        get { enabledLock.lock(); defer { enabledLock.unlock() }; return enabled }
        set { enabledLock.lock(); defer { enabledLock.unlock() }; enabled = newValue }
    }

    private let writeQueue = DispatchQueue(label: "com.textractor.telemetry", qos: .utility)
    private let dateFormatter: ISO8601DateFormatter
    private let encoder: JSONEncoder

    init(fileURL: URL? = nil) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")

        let dir = fileURL?.deletingLastPathComponent() ?? appSupport.appendingPathComponent("Textractor", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.fileURL = fileURL ?? dir.appendingPathComponent("telemetry.jsonl")

        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
    }

    // MARK: - API

    /// Records an event. Failures inside this method are swallowed — telemetry
    /// must never bring down the app.
    public func record(_ event: TelemetryEvent, telemetryEnabled: Bool) {
        guard telemetryEnabled, isEnabled else { return }
        writeQueue.async { [weak self] in
            guard let self, self.isEnabled else { return }
            do {
                let line = try self.encoder.encode(event)
                guard let json = String(data: line, encoding: .utf8) else { return }
                self.append(line: json + "\n")
            } catch {
                LoggerService.shared.debug("telemetry encode failure: \(error.localizedDescription)")
            }
        }
    }

    /// Stream-readable snapshot for the Settings UI.
    public func recent(limit: Int = 200) -> [TelemetryEvent] {
        writeQueue.sync {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let str = String(data: data, encoding: .utf8) else { return [] }
        let lines = str.split(separator: "\n").suffix(max(0, limit))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lines.compactMap { line in
            guard let lineData = String(line).data(using: .utf8) else { return nil }
            return try? decoder.decode(TelemetryEvent.self, from: lineData)
        }
        }
    }

    /// Truncates the log. Call from the Settings "Erase telemetry" button.
    public func wipe() {
        writeQueue.sync {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Internal

    private func append(line: String) {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                _ = try? handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    _ = try? handle.write(contentsOf: data)
                }
                try? handle.close()
            } else {
                _ = try? line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } else {
            _ = try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
