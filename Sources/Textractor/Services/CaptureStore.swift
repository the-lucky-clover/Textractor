import Foundation
import SwiftData
import CoreGraphics
import AppKit
import CryptoKit
import Security

#if canImport(Security)
import Security
#endif

/// Persistent model for a captured image with OCR text and metadata.
@Model
public final class CaptureRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var mode: String
    public var origin: String
    public var rect: String // JSON-encoded CGRect
    public var filePath: String
    
    // Encrypted fields
    public var ocrText: Data // AES-GCM ciphertext
    public var ocrNonce: Data // AES-GCM nonce
    public var decryptedocrText: String? // Cached plaintext (optional)
    
    public var language: String
    public var confidence: Double
    public var tags: [String]
    public var notes: String
    public var summary: String
    public var entities: [String] // JSON-encoded entities
    public var embedding: Data? // Vector embedding for semantic search
    public var fileSize: Int64
    public var imageWidth: Int
    public var imageHeight: Int
    public var isFavorite: Bool
    public var applicationName: String?
    public var windowTitle: String?
    
    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        mode: String,
        origin: String,
        rect: CGRect,
        filePath: String,
        ocrText: String = "",
        language: String = "",
        confidence: Double = 0.0,
        tags: [String] = [],
        notes: String = "",
        summary: String = "",
        entities: [String] = [],
        embedding: Data? = nil,
        fileSize: Int64 = 0,
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        isFavorite: Bool = false,
        applicationName: String? = nil,
        windowTitle: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.origin = origin
        self.rect = Self.encodeRect(rect)
        self.filePath = filePath
        // Store plaintext temporarily in decryptedocrText; CaptureStore.save() will encrypt it
        self.ocrText = Data()
        self.ocrNonce = Data()
        self.decryptedocrText = ocrText.isEmpty ? nil : ocrText
        self.language = language
        self.confidence = confidence
        self.tags = tags
        self.notes = notes
        self.summary = summary
        self.entities = entities
        self.embedding = embedding
        self.fileSize = fileSize
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.isFavorite = isFavorite
        self.applicationName = applicationName
        self.windowTitle = windowTitle
    }
    
    public var decodedRect: CGRect {
        Self.decodeRect(rect)
    }
    
    private static func encodeRect(_ rect: CGRect) -> String {
        let data = try? JSONEncoder().encode(["x": rect.origin.x, "y": rect.origin.y, "w": rect.size.width, "h": rect.size.height])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    
    private static func decodeRect(_ json: String) -> CGRect {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: CGFloat].self, from: data) else {
            return .zero
        }
        return CGRect(
            x: dict["x"] ?? 0,
            y: dict["y"] ?? 0,
            width: dict["w"] ?? 0,
            height: dict["h"] ?? 0
        )
    }
    
    /// Returns cached decrypted OCR text if available, otherwise empty string.
    /// The cache is populated by CaptureStore when fetching records.
    public var decryptedOcrText: String? {
        return decryptedocrText
    }
}

/// Manages the persistent capture library with SwiftData.
@MainActor
public final class CaptureStore: ObservableObject {
    
    public static let shared = CaptureStore()
    
    // MARK: - Keychain Keys
    private let keychain = Keychain()
    private let encryptionKeyIdentifier = "com.example.textractor.encryption.key"
    
    // Simplified direct key access for this implementation
    private func getEncryptionKey() throws -> SymmetricKey {
        // Try to get from keychain first
        if let keyData = keychain.data(forKey: encryptionKeyIdentifier) {
            return SymmetricKey(data: keyData)
        }
        // Otherwise generate new key and store
        let key = SymmetricKey(size: .bits256)
        try keychain.set(key.withUnsafeBytes { Data($0) }, forKey: encryptionKeyIdentifier)
        return key
    }
    
    private func encrypt(_ text: String) throws -> (ciphertext: Data, nonce: Data) {
        let key = try getEncryptionKey()
        let sealedBox = try AES.GCM.seal(text.data(using: .utf8)!, using: key)
        return (sealedBox.ciphertext, Data(sealedBox.nonce.withUnsafeBytes { $0 }))
    }
    
    private func decrypt(_ ciphertext: Data, nonce: Data) throws -> String {
        let key = try getEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: Data())
        var decryptedData = try AES.GCM.open(sealedBox, using: key)
        let plaintext = String(decoding: decryptedData, as: UTF8.self)
        // Securely wipe original data
        decryptedData.withUnsafeMutableBytes { ptr in
            for i in 0..<ptr.count { ptr[i] = 0 }
        }
        return plaintext
    }
    
    public let container: ModelContainer
    public let context: ModelContext
    
    @Published public var recentCaptures: [CaptureRecord] = []
    
    private init() {
        let schema = Schema([CaptureRecord.self])
        // Non-sandboxed app: use the app-private Application Support directory.
        // Using a group container here triggered a spurious "wants to access
        // data from other apps" TCC prompt because the group identifier was not
        // provisioned in entitlements. The app has no helper/extension to share
        // with, so an app-group container is both unnecessary and the cause of
        // the regression.
        let capturesDir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Textractor/Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: capturesDir, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            schema: schema,
            url: capturesDir.appendingPathComponent("captures.store"),
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: CaptureRecord.self, configurations: configuration)
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            fatalError("Failed to create CaptureStore: \(error)")
        }
    }
    
    /// Save a new capture record.
    public func save(_ record: CaptureRecord) throws {
        // Encrypt OCR text if provided as plaintext
        if let plaintext = record.decryptedocrText, record.ocrNonce.isEmpty {
            let (ciphertext, nonce) = try encrypt(plaintext)
            record.ocrText = ciphertext
            record.ocrNonce = nonce
            record.decryptedocrText = nil // Clear plaintext after encryption
        }
        context.insert(record)
        try context.save()
        refreshRecent()
    }
    
    /// Delete a capture record.
    public func delete(_ record: CaptureRecord) throws {
        context.delete(record)
        try context.save()
        refreshRecent()
    }
    
    /// Update an existing record.
    public func update(_ record: CaptureRecord) throws {
        try context.save()
        refreshRecent()
    }
    
    /// Fetch all captures sorted by date (newest first).
    public func fetchAll() -> [CaptureRecord] {
        let descriptor = FetchDescriptor<CaptureRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        decryptAndCacheOcrText(for: records)
        return records
    }
    
    /// Fetch captures within a date range.
    public func fetch(from startDate: Date, to endDate: Date) -> [CaptureRecord] {
        let descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.createdAt >= startDate && $0.createdAt <= endDate },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        decryptAndCacheOcrText(for: records)
        return records
    }
    
    /// Fetch captures matching a text query (simple contains).
    public func searchText(_ query: String) -> [CaptureRecord] {
        // First fetch all records, then filter in memory using decrypted text
        // (We can't use a predicate on encrypted Data)
        let allRecords = fetchAll()
        return allRecords.filter { record in
            let text = record.decryptedOcrText ?? ""
            return text.localizedStandardContains(query) ||
            record.notes.localizedStandardContains(query) ||
            record.summary.localizedStandardContains(query) ||
            record.tags.contains { $0.localizedStandardContains(query) }
        }
    }
    
    /// Fetch favorite captures.
    public func fetchFavorites() -> [CaptureRecord] {
        let descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        decryptAndCacheOcrText(for: records)
        return records
    }
    
    /// Fetch captures by tag.
    public func fetchByTag(_ tag: String) -> [CaptureRecord] {
        let descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.tags.contains(tag) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        decryptAndCacheOcrText(for: records)
        return records
    }
    
    /// Decrypt OCR text and cache it in `decryptedocrText` for each record.
    private func decryptAndCacheOcrText(for records: [CaptureRecord]) {
        guard !records.isEmpty else { return }
        do {
            for record in records {
                if !record.ocrText.isEmpty && !record.ocrNonce.isEmpty {
                    record.decryptedocrText = try decrypt(record.ocrText, nonce: record.ocrNonce)
                }
            }
        } catch {
            LoggerService.shared.warning("Failed to decrypt OCR text: \(error)")
        }
    }
    
    /// Refresh the recent captures cache.
    private func refreshRecent() {
        recentCaptures = fetchAll().prefix(50).map { $0 }
    }
    
    /// Get captures grouped by day for timeline view.
    public func groupedByDay() -> [Date: [CaptureRecord]] {
        let all = fetchAll()
        var grouped: [Date: [CaptureRecord]] = [:]
        let calendar = Calendar.current
        for record in all {
            let dayStart = calendar.startOfDay(for: record.createdAt)
            grouped[dayStart, default: []].append(record)
        }
        return grouped
    }
    
    /// Get captures grouped by week for timeline view.
    public func groupedByWeek() -> [Date: [CaptureRecord]] {
        let all = fetchAll()
        var grouped: [Date: [CaptureRecord]] = [:]
        let calendar = Calendar.current
        for record in all {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: record.createdAt)?.start ?? record.createdAt
            grouped[weekStart, default: []].append(record)
        }
        return grouped
    }
    
    /// Get captures grouped by month for timeline view.
    public func groupedByMonth() -> [Date: [CaptureRecord]] {
        let all = fetchAll()
        var grouped: [Date: [CaptureRecord]] = [:]
        let calendar = Calendar.current
        for record in all {
            let monthStart = calendar.dateInterval(of: .month, for: record.createdAt)?.start ?? record.createdAt
            grouped[monthStart, default: []].append(record)
        }
        return grouped
    }
    
    /// Get captures grouped by year for timeline view.
    public func groupedByYear() -> [Date: [CaptureRecord]] {
        let all = fetchAll()
        var grouped: [Date: [CaptureRecord]] = [:]
        let calendar = Calendar.current
        for record in all {
            let yearStart = calendar.dateInterval(of: .year, for: record.createdAt)?.start ?? record.createdAt
            grouped[yearStart, default: []].append(record)
        }
        return grouped
    }
    
    /// Delete all captures (for testing/reset).
    public func deleteAll() throws {
        let all = fetchAll()
        for record in all {
            context.delete(record)
        }
        try context.save()
        refreshRecent()
    }
    
    /// Total count of captures.
    public var totalCount: Int {
        (try? context.fetchCount(FetchDescriptor<CaptureRecord>())) ?? 0
    }
    
    /// Total storage size of captured images.
    public var totalFileSize: Int64 {
        fetchAll().reduce(0) { $0 + $1.fileSize }
    }
}

// MARK: - Keychain Service (Standalone Helper)
public final class Keychain {
    private let tag = "com.example.textractor"
    
    public func set(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Update existing item
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            if updateStatus != errSecSuccess {
                throw keychainError(updateStatus)
            }
        } else if status != errSecSuccess {
            throw keychainError(status)
        }
    }
    
    public func data(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? (result as? Data) : nil
    }
    
    public func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw keychainError(status)
        }
    }
}

public enum keychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    
    public init(_ status: OSStatus) {
        self = .unexpectedStatus(status)
    }
    
    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Unexpected Keychain status: \(status)"
        }
    }
}