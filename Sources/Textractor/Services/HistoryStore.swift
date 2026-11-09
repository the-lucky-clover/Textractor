import Foundation
import Combine

/// Stores a rolling history of extracted text and source-image paths. Bounded by
/// `AppSettings.historyEntryLimit` (slider 10…1000).
///
/// Text is stored in plaintext JSON. Successful source images currently remain
/// in the capture temporary directory for re-OCR while those files are available.
/// Clearing text history does not erase the system temporary directory. Failed
/// images live in the separate recovery folder managed by `CacheService`.
@MainActor
public final class HistoryStore: ObservableObject {

    public static let shared = HistoryStore()

    @Published public private(set) var records: [HistoryRecord] = []
    @Published public private(set) var storageError: String?
    private var loadFailed = false

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

    /// File-backed test store, also useful for migration verification.
    init(directory: URL) {
        self.directory = directory
        self.metadataURL = directory.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        recomputeSize()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return }
        do {
            let data = try Data(contentsOf: metadataURL)
            records = try JSONDecoder().decode([HistoryRecord].self, from: data)
        } catch {
            loadFailed = true
            storageError = "Saved history could not be read. Its original file has been retained; new captures can still be copied, but history writes are paused. Back up history.json before using Clear history to start again."
        }
    }

    private func save() {
        guard !loadFailed else { return }
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: metadataURL, options: .atomic)
            storageError = nil
        } catch {
            storageError = "History could not be saved: \(error.localizedDescription)"
        }
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
        guard !loadFailed else { return }
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
        guard !loadFailed else { return }
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
        // Imports and reprocessing may arrive out of timestamp order.
        records.sort { $0.capturedAt > $1.capturedAt }
        enforceLimit(limit)
        save()
    }

    public func delete(_ record: HistoryRecord) {
        guard !loadFailed else { return }
        if let p = record.textPath {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: p))
        }
        records.removeAll { $0.id == record.id }
        save()
    }

    /// Wipe every record. Used by Settings → "Clear history".
    public func clearAll() {
        // Clear history is an explicit, confirmed user action. Only this path
        // may replace an unreadable archive with a new empty history.
        loadFailed = false
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
        guard !loadFailed else { return }
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
