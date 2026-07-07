import Foundation

/// Self-describing event for the local telemetry pipeline. Persisted as JSONL
/// to `~/Library/Application Support/Textractor/telemetry.jsonl`.
public struct TelemetryEvent: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case sessionStart
        case sessionEnd
        case hotkeyPressed
        case captureRegion
        case captureWindow
        case captureCancelled
        case ocrAttempt
        case ocrSuccess
        case ocrFailure
        case ocrRetry
        case aiAnalysis
        case clipboardWrite
        case clipboardFailure
        case storageSaved
        case storageDeleted
        case shareEmail
        case shareMessage
        case shareAirDrop
        case shareOther
        case permissionMissing
        case settingsChanged
        case festiveNudge           // psychological-addictiveness hook
    }

    public let id: UUID
    public let timestamp: Date
    public let kind: Kind
    public let success: Bool
    public let latencyMs: Double?
    public let meta: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        success: Bool = true,
        latencyMs: Double? = nil,
        meta: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.success = success
        self.latencyMs = latencyMs
        self.meta = meta
    }
}
