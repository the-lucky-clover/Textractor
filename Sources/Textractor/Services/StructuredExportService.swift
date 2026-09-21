import AppKit
import Foundation
import UniformTypeIdentifiers

/// Service for exporting history records in various structured formats:
/// - JSON: Full structured data with metadata
/// - CSV: Flat table format suitable for spreadsheets
/// - Markdown: Human-readable format with formatting
///
/// This enables users to move their captured text into other apps
/// like Notion, Obsidian, Excel, or any data processing tool.
@MainActor
public final class StructuredExportService: ObservableObject {

    public static let shared = StructuredExportService()

    private weak var coordinator: AppCoordinator?

    private init() {}

    public func configure(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Export Format Definition

    public enum ExportFormat: String, CaseIterable, Identifiable {
        case json = "JSON"
        case csv = "CSV"
        case markdown = "Markdown"

        public var id: String { rawValue }

        public var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv: return "csv"
            case .markdown: return "md"
            }
        }

        public var utType: UTType {
            switch self {
            case .json: return .json
            case .csv: return .commaSeparatedText
            case .markdown: return .plainText
            }
        }

        public var description: String {
            switch self {
            case .json: return "Full structured data with metadata"
            case .csv: return "Table format for spreadsheets"
            case .markdown: return "Formatted text with headers"
            }
        }
    }

    // MARK: - Export Single Record

    public func export(record: HistoryRecord, format: ExportFormat) -> Data? {
        switch format {
        case .json: return exportJSON(record: record)
        case .csv: return exportCSV(record: record)
        case .markdown: return exportMarkdown(record: record)
        }
    }

    public func exportString(record: HistoryRecord, format: ExportFormat) -> String? {
        guard let data = export(record: record, format: format),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    // MARK: - Export All Records

    public func exportAll(format: ExportFormat) -> Data? {
        guard let coordinator = coordinator else { return nil }
        let records = HistoryStore.shared.records

        switch format {
        case .json:
            return exportJSON(records: records)
        case .csv:
            return exportCSV(records: records)
        case .markdown:
            return exportMarkdown(records: records)
        }
    }

    // MARK: - JSON Export

    private func exportJSON(record: HistoryRecord) -> Data? {
        let exportRecord = ExportRecord(from: record)
        return try? JSONEncoder().encode(exportRecord)
    }

    private func exportJSON(records: [HistoryRecord]) -> Data? {
        let exportRecords = records.map { ExportRecord(from: $0) }
        return try? JSONEncoder().encode(exportRecords)
    }

    // MARK: - CSV Export

    private func exportCSV(record: HistoryRecord) -> Data? {
        exportCSV(records: [record])
    }

    private func exportCSV(records: [HistoryRecord]) -> Data? {
        var lines: [String] = []

        // Header row
        lines.append("ID,Timestamp,Mode,TextPreview,FullText")

        // Data rows
        for record in records {
            let id = escapeCSV(record.id.uuidString)
            let timestamp = escapeCSV(formatTimestamp(record.capturedAt))
            let mode = escapeCSV(record.mode.rawValue)
            let preview = escapeCSV(String(record.textPreview.prefix(200)))
            let fullText = escapeCSV(record.textPreview)

            lines.append("\(id),\(timestamp),\(mode),\(preview),\(fullText)")
        }

        return lines.joined(separator: "\n").data(using: .utf8)
    }

    private func escapeCSV(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\"", with: "\"\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        if escaped.contains(",") || escaped.contains("\"") || escaped.contains(" ") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    // MARK: - Markdown Export

    private func exportMarkdown(record: HistoryRecord) -> Data? {
        exportMarkdown(records: [record])
    }

    private func exportMarkdown(records: [HistoryRecord]) -> Data? {
        var lines: [String] = []

        lines.append("# Textractor Export")
        lines.append("")
        lines.append("*Exported on \(formatTimestamp(Date()))*")
        lines.append("")
        lines.append("---\n")

        for (index, record) in records.enumerated() {
            lines.append("## \(index + 1). \(record.mode.rawValue.capitalized)")
            lines.append("")
            lines.append("**Captured:** \(formatTimestamp(record.capturedAt))")
            lines.append("")
            lines.append("```")
            lines.append(record.textPreview)
            lines.append("```")
            lines.append("")
            lines.append("*ID: \(record.id.uuidString)*")
            lines.append("")
            lines.append("---\n")
        }

        return lines.joined(separator: "\n").data(using: .utf8)
    }

    // MARK: - Save to File

    public func saveToFile(record: HistoryRecord, format: ExportFormat, panelTitle: String) {
        let savePanel = NSSavePanel()
        savePanel.title = panelTitle
        savePanel.nameFieldStringValue = "Textractor-\(formatTimestamp(Date())).\(format.fileExtension)"
        savePanel.allowedContentTypes = [format.utType]

        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            guard let data = self?.export(record: record, format: format) else { return }

            do {
                try data.write(to: url)
                LoggerService.shared.info("Exported record to \(url.path)")
            } catch {
                LoggerService.shared.error("Export failed: \(error.localizedDescription)")
            }
        }
    }

    public func saveAllToFile(format: ExportFormat, panelTitle: String) {
        let savePanel = NSSavePanel()
        savePanel.title = panelTitle
        savePanel.nameFieldStringValue = "Textractor-Export-\(formatTimestamp(Date())).\(format.fileExtension)"
        savePanel.allowedContentTypes = [format.utType]

        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            guard let data = self?.exportAll(format: format) else { return }

            do {
                try data.write(to: url)
                LoggerService.shared.info("Exported all records to \(url.path)")
            } catch {
                LoggerService.shared.error("Export failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Copy to Clipboard

    public func copyToClipboard(record: HistoryRecord, format: ExportFormat) -> Bool {
        guard let string = exportString(record: record, format: format) else { return false }
        return ClipboardService.shared.copy(string, plainTextOnly: true)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Export Data Models

struct ExportRecord: Codable {
    let id: String
    let capturedAt: String
    let mode: String
    let textPreview: String
    let ocrConfidence: Float?

    init(from record: HistoryRecord) {
        self.id = record.id.uuidString
        let formatter = ISO8601DateFormatter()
        self.capturedAt = formatter.string(from: record.capturedAt)
        self.mode = record.mode.rawValue
        self.textPreview = record.textPreview
        self.ocrConfidence = record.ocrConfidence
    }
}