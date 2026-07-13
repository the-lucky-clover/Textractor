//
//  ExtractionRecord.swift
//  Textractor
//
//  Persistent data record of a single OCR extraction. Persisted as JSON via HistoryManager.
//

import Foundation
import SwiftUI

struct ExtractionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    var extractedText: String
    var confidence: Double          // 0.0–1.0 aggregate confidence
    var language: String
    var characterCount: Int
    var wordCount: Int
    var lineCount: Int
    var processingTimeMs: Double
    var healedCorrections: [CorrectionEntry]
    var sourceBundleIdentifier: String?
    var status: ExtractionStatus

    init(
        text: String,
        confidence: Double,
        language: String,
        processingTimeMs: Double,
        healedCorrections: [CorrectionEntry] = [],
        sourceBundleIdentifier: String? = nil,
        status: ExtractionStatus = .success
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.extractedText = text
        self.confidence = confidence
        self.language = language
        self.characterCount = text.count
        self.wordCount = text.isEmpty ? 0 : text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        self.lineCount = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
        self.processingTimeMs = processingTimeMs
        self.healedCorrections = healedCorrections
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.status = status
    }

    var formattedTime: String {
        let f = DateFormatter()
        f.timeStyle = .medium
        return f.string(from: timestamp)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: timestamp)
    }

    var confidencePercentage: String {
        String(format: "%.1f%%", confidence * 100)
    }

    var previewText: String {
        String(extractedText.prefix(120))
    }
}

// MARK: - Correction Entry

struct CorrectionEntry: Codable, Hashable {
    let original: String
    let corrected: String
    let rule: String       // name of the heuristic rule that fired
    let confidenceDelta: Double
}

// MARK: - Extraction Status

enum ExtractionStatus: String, Codable {
    case success
    case partial
    case failed
    case empty
    case healed

    var label: String {
        switch self {
        case .success:  return "Extracted"
        case .partial:  return "Partial"
        case .failed:   return "Failed"
        case .empty:    return "No Text"
        case .healed:   return "Healed"
        }
    }

    var color: Color {
        switch self {
        case .success:  return BreakingDad.toxicGreen
        case .partial:  return BreakingDad.hazmatYellow
        case .failed:   return BreakingDad.rust
        case .empty:    return BreakingDad.chalk.opacity(0.5)
        case .healed:   return BreakingDad.methBlue
        }
    }
}
