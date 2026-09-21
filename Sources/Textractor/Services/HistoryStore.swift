import Foundation
import Combine

/// Stores a rolling history of *extracted text only* per capture. Bounded by
/// `AppSettings.historyEntryLimit` (slider 10…1000).
///
/// As of Textractor 2.x, capture screenshots are *never* retained — OCR'd text
/// is the only durable artefact of a capture, and the user's machine is left
/// with no surprises. The `directory` only ever holds `*.txt` payloads (also
/// optional — the text lives inline in `records` for instant reads).
/// "Cache" lifetime data (the screenshots Textractor failed to extract, kept
/// for the user to retry) is unrelated to history and lives under
/// `~/Pictures/Textractor Screenshots/`; `CacheService` is responsible for that.
@MainActor
public final class HistoryStore: ObservableObject {

    public static let shared = HistoryStore()

    @Published public private(set) var records: [HistoryRecord] = []

    private let directory: URL
    private let metadataURL: URL
    private let maxRecordsCeiling: Int = 1_000

    /// Cached on reads — the toast's "X clear" button and Settings size
    /// indicator both poll this.
    @Published public private(set) var cachedByteCount: Int = 0

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("Textractor/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        metadataURL = directory.appendingPathComponent("history.json")
        load()
        recomputeSize()

        // Subscribe to settings changes to enforce limit when user lowers it.
        SettingsStore.shared.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] (settings: AppSettings) in
                self?.enforceLimit(settings.historyEntryLimit)
            }
            .store(in: &cancellables)
    }

    /// Create an in-memory store for testing (no disk persistence).
    public init(inMemory: Bool) {
        if inMemory {
            let base = URL(fileURLWithPath: NSTemporaryDirectory())
            directory = base.appendingPathComponent("Textractor/History/Test_\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            metadataURL = directory.appendingPathComponent("history.json")
            records = []
            cachedByteCount = 0
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            directory = base.appendingPathComponent("Textractor/History", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            metadataURL = directory.appendingPathComponent("history.json")
            load()
            recomputeSize()

            SettingsStore.shared.$current
                .receive(on: RunLoop.main)
                .sink { [weak self] (settings: AppSettings) in
                    self?.enforceLimit(settings.historyEntryLimit)
                }
                .store(in: &cancellables)
        }
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
        recomputeSize()
    }

    /// Walk the records and sum the size of every on-disk `.txt` file plus the
    /// metadata blob. Cheap; runs after every mutation.
    private func recomputeSize() {
        var bytes = 0
        let fm = FileManager.default
        for record in records {
            if let p = record.textPath,
               let attrs = try? fm.attributesOfItem(atPath: p),
               let size = attrs[.size] as? Int {
                bytes += size
            }
        }
        if let attrs = try? fm.attributesOfItem(atPath: metadataURL.path),
           let size = attrs[.size] as? Int {
            bytes += size
        }
        cachedByteCount = bytes
    }

    // MARK: - Limit

    /// Re-bounds the in-memory history to the requested limit. Drops oldest.
    public func enforceLimit(_ limit: Int) {
        let clamped = max(1, min(maxRecordsCeiling, limit))
        guard records.count > clamped else { return }
        let overflow = records.suffix(from: clamped)
        for old in overflow {
            if let p = old.textPath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: p))
            }
        }
        records = Array(records.prefix(clamped))
        save()
    }

    // MARK: - Mutations

    /// Append a new entry. The `CapturedImage` is only used for id / timestamp.
    public func record(capture: CapturedImage,
                       text: String,
                       mode: CaptureMode,
                       ocrConfidence: Float? = nil,
                       imagePath: String? = nil,
                       limit: Int) {
        let record = HistoryRecord(
            id: capture.id,
            capturedAt: capture.capturedAt,
            textPreview: text,
            mode: mode,
            ocrConfidence: ocrConfidence,
            textPath: nil,
            imagePath: imagePath ?? capture.fileURL.path
        )
        records.insert(record, at: 0)
        enforceLimit(limit)
        save()
    }

    public func delete(_ record: HistoryRecord) {
        if let p = record.textPath {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: p))
        }
        records.removeAll { $0.id == record.id }
        save()
    }

    /// Wipe every record. Used by Settings → "Clear history".
    public func clearAll() {
        for r in records {
            if let path = r.textPath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
        }
        records.removeAll()
        save()
        recomputeSize()
    }

    /// Undo the most recent capture (for toast undo action).
    /// Removes the most recent record from history.
    public func undoLastCapture() {
        guard !records.isEmpty else { return }
        let removed = records.removeFirst()
        if let path = removed.textPath {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
        save()
    }

    /// Public accessor — used by RecoverySheet to refresh the published count.
    public func refresh() {
        recomputeSize()
    }
}
