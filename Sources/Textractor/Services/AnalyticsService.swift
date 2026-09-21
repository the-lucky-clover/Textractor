import Foundation
import OSLog
import SwiftData // For CaptureRecord and related models

/// `AnalyticsService` provides lightweight, privacy-first local analytics.
/// 
/// **Key Principles:**
/// - **No network calls ever** — all data stays on device
/// - **No user identification** — no IDs, no tracking cookies
/// - **Aggregate counts only** — error type → count, no payloads
/// - **User-controlled** — can be disabled, data can be wiped
/// - **Useful for debugging** — helps users understand "how often does X fail"
/// 
/// Thread-safe via serial queue.
public final class AnalyticsService {
    public static let shared = AnalyticsService()

    private let subsystem = "com.textractor.app"
    private let category = "Analytics"

    private var osLogger: Logger
    
    // MARK: - In-memory counters
    private var errorCounts: [ErrorCategory: Int] = [:]
    private var captureCounts: [CaptureMode: Int] = [:]
    private var ocrLanguageCounts: [String: Int] = [:]
    
    // MARK: - Persistence
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.textractor.analytics", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        osLogger = Logger(subsystem: subsystem, category: category)
        
        // Store in Caches so it's cleaned up automatically
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let analyticsDir = cacheDir.appendingPathComponent("Textractor/Analytics", isDirectory: true)
        try? FileManager.default.createDirectory(at: analyticsDir, withIntermediateDirectories: true)
        fileURL = analyticsDir.appendingPathComponent("analytics.json")
        
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        loadFromDisk()
    }
    
    // MARK: - Public API
    
    /// Increment an error counter for a given category.
    /// Call this whenever you catch an error you want to track locally.
    /// - Parameter category: The type of error (e.g., .captureFailed, .ocrFailed, .clipboardFailed)
    public func recordError(_ category: ErrorCategory) {
        queue.async {
            self.errorCounts[category, default: 0] += 1
            self.persist()
        }
    }
    
    /// Record a successful capture by mode.
    /// - Parameter mode: The capture mode used (.crosshair, .window)
    public func recordCapture(mode: CaptureMode) {
        queue.async {
            self.captureCounts[mode, default: 0] += 1
            self.persist()
        }
    }
    
    /// Record an OCR language used.
    /// - Parameter language: The BCP-47 language code (e.g., "en-US", "es-ES")
    public func recordOCRLanguage(_ language: String) {
        queue.async {
            self.ocrLanguageCounts[language, default: 0] += 1
            self.persist()
        }
    }
    
    /// Get all error counts as a dictionary.
    public func getErrorCounts() -> [ErrorCategory: Int] {
        queue.sync { errorCounts }
    }
    
    /// Get all capture mode counts.
    public func getCaptureCounts() -> [CaptureMode: Int] {
        queue.sync { captureCounts }
    }
    
    /// Get OCR language usage counts.
    public func getOCRLanguageCounts() -> [String: Int] {
        queue.sync { ocrLanguageCounts }
    }
    
    /// Get a human-readable summary for debugging display.
    public func getSummary() -> String {
        var result = ""
        queue.sync {
            var lines: [String] = ["📊 Local Analytics Summary"]
            
            if errorCounts.isEmpty && captureCounts.isEmpty && ocrLanguageCounts.isEmpty {
                lines.append("  (no data yet)")
                result = lines.joined(separator: "\n")
                return
            }
            
            if !errorCounts.isEmpty {
                lines.append("  Errors:")
                for (cat, count) in errorCounts.sorted(by: { $0.value > $1.value }) {
                    lines.append("    \(cat.rawValue): \(count)")
                }
            }
            
            if !captureCounts.isEmpty {
                lines.append("  Captures:")
                for (mode, count) in captureCounts.sorted(by: { $0.value > $1.value }) {
                    lines.append("    \(mode.analyticsDisplayName): \(count)")
                }
            }
            
            if !ocrLanguageCounts.isEmpty {
                lines.append("  OCR Languages:")
                for (lang, count) in ocrLanguageCounts.sorted(by: { $0.value > $1.value }).prefix(5) {
                    lines.append("    \(lang): \(count)")
                }
            }
            
            result = lines.joined(separator: "\n")
        }
        return result
    }
    
    /// Wipe all analytics data. Called from Settings "Clear Local Analytics".
    public func wipe() {
        queue.async {
            self.errorCounts.removeAll()
            self.captureCounts.removeAll()
            self.ocrLanguageCounts.removeAll()
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }
    
    // MARK: - Private
    
    private func persist() {
        let snapshot = AnalyticsSnapshot(
            errorCounts: errorCounts,
            captureCounts: captureCounts,
            ocrLanguageCounts: ocrLanguageCounts,
            timestamp: Date()
        )
        
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            osLogger.error("Failed to persist analytics: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(AnalyticsSnapshot.self, from: data)
            errorCounts = snapshot.errorCounts
            captureCounts = snapshot.captureCounts
            ocrLanguageCounts = snapshot.ocrLanguageCounts
        } catch {
            osLogger.warning("Failed to load analytics: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Supporting Types

/// Categories of errors we track locally.
public enum ErrorCategory: String, Codable, CaseIterable, Sendable {
    case captureFailed = "Capture Failed"
    case ocrFailed = "OCR Failed"
    case ocrEmptyResult = "OCR Empty Result"
    case clipboardFailed = "Clipboard Failed"
    case fileWriteFailed = "File Write Failed"
    case permissionDenied = "Permission Denied"
    case aiProcessingFailed = "AI Processing Failed"
    case localLLMFailed = "Local LLM Failed"
    case continuityCaptureFailed = "Continuity Capture Failed"
    case unknown = "Unknown"
    
    var displayName: String { rawValue }
}

// Use existing CaptureMode from Models/CaptureMode.swift
// This enum tracks capture modes for analytics purposes
public extension CaptureMode {
    /// Analytics-friendly display name for capture modes
    var analyticsDisplayName: String {
        switch self {
        case .crosshair: return "Region"
        case .window: return "Window"
        case .autoScroll: return "Auto-Scroll"
        }
    }
}

/// Snapshot for disk persistence.
private struct AnalyticsSnapshot: Codable {
    let errorCounts: [ErrorCategory: Int]
    let captureCounts: [CaptureMode: Int]
    let ocrLanguageCounts: [String: Int]
    let timestamp: Date
}