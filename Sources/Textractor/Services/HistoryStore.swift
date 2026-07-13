import Foundation
import Combine

/// Persists a rolling history of captures (extracted text + a retained copy of
/// each screenshot PNG) under `~/Library/Application Support/Textractor/History`.
///
/// The store keeps its own copy of every screenshot so history survives even
/// when the user's storage mode would otherwise trash the original file. It is
/// an `ObservableObject` so SwiftUI views can react to changes.
public final class HistoryStore: ObservableObject {

    public static let shared = HistoryStore()

    @Published public private(set) var records: [HistoryRecord] = []

    private let directory: URL
    private let metadataURL: URL
    private let maxRecords = 250

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("Textractor/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        metadataURL = directory.appendingPathComponent("history.json")
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([HistoryRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - Mutations

    /// Copy the screenshot (if still present) into the history directory and
    /// prepend a record. Synchronous so the file is captured before any
    /// per-capture storage decision can delete the original.
    public func record(capture: CapturedImage, text: String, mode: CaptureMode) {
        var screenshotPath: String?
        if FileManager.default.fileExists(atPath: capture.fileURL.path) {
            let dest = directory.appendingPathComponent("\(capture.id.uuidString).png")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: capture.fileURL, to: dest)) != nil {
                screenshotPath = dest.path
            }
        }
        let record = HistoryRecord(
            id: capture.id,
            capturedAt: capture.capturedAt,
            textPreview: text,
            mode: mode,
            screenshotPath: screenshotPath
        )
        records.insert(record, at: 0)
        if records.count > maxRecords {
            let overflow = records.suffix(from: maxRecords)
            for old in overflow {
                if let p = old.screenshotPath { try? FileManager.default.removeItem(at: URL(fileURLWithPath: p)) }
            }
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    public func delete(_ record: HistoryRecord) {
        if let p = record.screenshotPath { try? FileManager.default.removeItem(at: URL(fileURLWithPath: p)) }
        records.removeAll { $0.id == record.id }
        save()
    }

    public func clear() {
        for r in records where r.screenshotPath != nil {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: r.screenshotPath!))
        }
        records.removeAll()
        save()
    }
}
