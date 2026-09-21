import SwiftUI
import AppKit

/// The main "History" window. Shows a grid of past captures as screenshot
/// thumbnails with their extracted text. On open the cards stagger in; on close
/// they stagger out before the window actually dismisses.
public struct HistoryView: View {

    @StateObject private var store = HistoryStore.shared

    @State private var appeared = false
    @State private var closing = false
    @State private var searchText = ""
    @State private var selectedModeFilter: CaptureMode? = nil
    @State private var showFilters = false

    /// Called once the closing animation has finished; the window controller
    /// uses it to actually close the window.
    var onClose: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)]

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchAndFilters
            Divider()
            content
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 460, idealHeight: 560)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text("History")
                .font(.headline)
            if !filteredRecords.isEmpty {
                Text("\(filteredRecords.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            Spacer()
            if !store.records.isEmpty {
                Toggle(isOn: $showFilters) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16))
                }
                .toggleStyle(.button)
                .help("Show filters")
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.clearAll() }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear history")
            }
            Button {
                requestClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(12)
    }

    // MARK: - Search & Filters

    private var searchAndFilters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)

            if showFilters {
                let modeOptions: [CaptureMode?] = [nil] + CaptureMode.allCases
                HStack(spacing: 12) {
                    Text("Mode:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $selectedModeFilter) {
                        ForEach(modeOptions, id: \.self) { mode in
                            Text(mode?.label ?? "All").tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)

                    Text("Date:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: .constant(Date()), displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 150)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showFilters)
    }

    /// Filtered records based on search text and filters
    private var filteredRecords: [HistoryRecord] {
        store.records.filter { record in
            // Search text filter
            if !searchText.isEmpty {
                let text = record.textPreview.localizedCaseInsensitiveContains(searchText)
                let date = record.capturedAt.formatted(date: .abbreviated, time: .shortened).localizedCaseInsensitiveContains(searchText)
                if !text && !date { return false }
            }
            // Mode filter
            if let modeFilter = selectedModeFilter, record.mode != modeFilter {
                return false
            }
            return true
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if store.records.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 42))
                    .foregroundStyle(.tertiary)
                Text(T.s("history.empty"))
                    .foregroundStyle(.secondary)
                Text(T.s("history.empty.hint"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(filteredRecords.enumerated()), id: \.element.id) { index, record in
                        HistoryCard(
                            record: record,
                            index: index,
                            appeared: appeared,
                            closing: closing,
                            onTap: {
                                ClipboardService.shared.copy(record.textPreview, attributed: nil, plainTextOnly: true)
                                SoundManager.playCaptureComplete()
                            },
                            onDelete: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.delete(record) }
                            },
                            onReOCR: {
                                guard let path = record.imagePath else { return }
                                Task {
                                    await AppCoordinator.shared.reOCR(imagePath: path)
                                }
                            }
                        )
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Closing

    private func requestClose() {
        closing = true
        let total = Double(min(store.records.count, 40)) * 0.025 + 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { onClose() }
    }
}

/// The main "History" window. Shows a grid of past captures as screenshot
/// thumbnails with their extracted text. On open the cards stagger in; on close
/// they stagger out before the window actually dismisses.
private struct HistoryCard: View {

    let record: HistoryRecord
    let index: Int
    let appeared: Bool
    let closing: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onReOCR: () -> Void

    @State private var hovered = false

    /// Single animation token so appear/closing share one `.animation` modifier
    /// (avoids conflicting per-property animations).
    private var animKey: Int { (appeared ? 1 : 0) + (closing ? 2 : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: CaptureMode(rawValue: record.mode.rawValue)?.symbolName ?? "doc")
                    .foregroundStyle(BreakingDad.toxicGreen)
                Text(record.capturedAt, style: .date)
                Text(record.capturedAt, style: .time)
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(record.textPreview.isEmpty ? "(no text)" : record.textPreview)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovered ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(hovered ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Delete", action: onDelete)
            if record.imagePath != nil {
                Button("Re-OCR", action: onReOCR)
            }
            Divider()
            Button("Export as Markdown") {
                exportRecord(record, format: .markdown)
            }
            Button("Export as JSON") {
                exportRecord(record, format: .json)
            }
            Button("Export as CSV") {
                exportRecord(record, format: .csv)
            }
        }
        .overlay(deleteButton, alignment: .topTrailing)
        .opacity(closing ? 0 : (appeared ? 1 : 0))
        .offset(y: closing ? 8 : (appeared ? 0 : 12))
        .scaleEffect(closing ? 0.96 : 1)
        .animation(.spring(response: 0.42, dampingFraction: 0.8).delay(Double(index) * 0.035), value: animKey)
    }

    /// Export format options
    private enum ExportFormat {
        case markdown, json, csv
    }

    /// Export a single history record in the specified format
    private func exportRecord(_ record: HistoryRecord, format: ExportFormat) {
        let savePanel = NSSavePanel()
        let timestamp = ISO8601DateFormatter().string(from: record.capturedAt).replacingOccurrences(of: ":", with: "-")
        savePanel.nameFieldStringValue = "Textractor_\(record.id.uuidString.prefix(8))_\(timestamp)"

        switch format {
        case .markdown:
            savePanel.allowedContentTypes = [.text]
            savePanel.nameFieldStringValue += ".md"
        case .json:
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue += ".json"
        case .csv:
            savePanel.allowedContentTypes = [.commaSeparatedText]
            savePanel.nameFieldStringValue += ".csv"
        }

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            let content: String
            switch format {
            case .markdown:
                content = Self.generateMarkdown(record)
            case .json:
                content = Self.generateJSON(record)
            case .csv:
                content = Self.generateCSV(record)
            }

            try? content.write(to: url, atomically: true, encoding: .utf8)
            SoundManager.playCaptureComplete()
        }
    }

    static func generateMarkdown(_ record: HistoryRecord) -> String {
        var md = ""
        md += "# Textractor Capture\n\n"
        md += "**ID:** \(record.id.uuidString)\n"
        md += "**Date:** \(record.capturedAt.formatted())\n"
        md += "**Mode:** \(CaptureMode(rawValue: record.mode.rawValue)?.label ?? record.mode.rawValue)\n"
        md += "**Confidence:** \(String(format: "%.1f%%", (record.ocrConfidence ?? 0) * 100))\n"
        md += "\n## Extracted Text\n\n"
        md += "```\n\(record.textPreview)\n```\n"
        return md
    }

    static func generateJSON(_ record: HistoryRecord) -> String {
        let dict: [String: Any] = [
            "id": record.id.uuidString,
            "capturedAt": ISO8601DateFormatter().string(from: record.capturedAt),
            "mode": record.mode.rawValue,
            "textPreview": record.textPreview,
            "ocrConfidence": record.ocrConfidence ?? 0,
            "imagePath": record.imagePath ?? "",
            "textPath": record.textPath ?? ""
        ]
        let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? "{}"
    }

    static func generateCSV(_ record: HistoryRecord) -> String {
        let escapedText = record.textPreview.replacingOccurrences(of: "\"", with: "\"\"")
        let headers = "id,date,mode,textPreview,confidence,imagePath,textPath"
        let row = "\"\(record.id.uuidString)\",\"\(ISO8601DateFormatter().string(from: record.capturedAt))\",\"\(record.mode.rawValue)\",\"\(escapedText)\",\"\(record.ocrConfidence ?? 0)\",\"\(record.imagePath ?? "")\",\"\(record.textPath ?? "")\""
        return "\(headers)\n\(row)"
    }

    @ViewBuilder private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .background(Circle().fill(.background))
        }
        .buttonStyle(.plain)
        .opacity(hovered ? 1 : 0)
        .padding(6)
    }
}