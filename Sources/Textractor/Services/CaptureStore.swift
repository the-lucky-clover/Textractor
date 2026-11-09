import Foundation
import SwiftData
import CoreGraphics
import AppKit
import CryptoKit
import Security

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
    // Retain the original stored field so older SwiftData stores keep their schema.
    // It is read only for migration and cleared before the library becomes available.
    // Never put newly decrypted text in this legacy field.
    var decryptedocrText: String?
    @Transient public var decryptedOcrText: String? = nil
    
    /// Key metadata retained for existing records; missing keys never trigger rotation.
    public var keyVersion: Int
    
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
        windowTitle: String? = nil,
        keyVersion: Int = 1
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.origin = origin
        self.rect = Self.encodeRect(rect)
        self.filePath = filePath
        // The plaintext exists only in memory; save encrypts it before insertion.
        self.ocrText = Data()
        self.ocrNonce = Data()
        self.decryptedocrText = nil
        self.decryptedOcrText = ocrText.isEmpty ? nil : ocrText
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
        self.keyVersion = keyVersion
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
    
}

/// The injectable interface keeps persistence tests out of the user's real Keychain.
protocol CaptureKeyStoring: AnyObject {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
}

public enum CaptureLibraryError: Error, LocalizedError {
    case unavailable
    case missingEncryptionKey
    case invalidEncryptionKey
    case invalidKeyVersion

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The capture library could not be opened. Its existing files have been kept. Check disk space and file access, then try again."
        case .missingEncryptionKey:
            return "The capture library's encryption key is missing. Restore the original login keychain before saving more captures. Existing records have been kept."
        case .invalidEncryptionKey, .invalidKeyVersion:
            return "The capture library's encryption information could not be read. Existing records and keys have been kept. Restore the original login keychain, then try again."
        }
    }
}

/// Manages the persistent capture library with SwiftData.
@MainActor
public final class CaptureStore: ObservableObject {
    
    public static let shared = CaptureStore()
    
    // Keep these identifiers unchanged so existing users retain their encryption key.
    static let encryptionKeyIdentifier = "com.example.textractor.encryption.key"
    static let keyVersionIdentifier = "com.example.textractor.encryption.keyVersion"
    private let keychain: CaptureKeyStoring
    private let directory: URL
    private var container: ModelContainer?
    private(set) var context: ModelContext?
    private var openingError: Error?

    @Published public var recentCaptures: [CaptureRecord] = []
    @Published public private(set) var storageError: String?
    public var isAvailable: Bool { context != nil }

    init(directory: URL? = nil, keychain: CaptureKeyStoring = Keychain()) {
        self.directory = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Textractor/Captures", isDirectory: true)
        self.keychain = keychain
        openStore()
    }

    /// Failure leaves the original store untouched and the rest of the app usable.
    /// There is deliberately no destructive recreation or in-memory success fallback.
    private func openStore() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let schema = Schema([CaptureRecord.self])
            let configuration = ModelConfiguration(
                schema: schema,
                url: directory.appendingPathComponent("captures.store"),
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let openedContainer = try ModelContainer(for: CaptureRecord.self, configurations: configuration)
            let openedContext = ModelContext(openedContainer)
            // Every mutation must pass through an explicit save/error path.
            openedContext.autosaveEnabled = false
            container = openedContainer
            context = openedContext
            try migrateLegacyPlaintext(in: openedContext)
            openingError = nil
            storageError = nil
        } catch {
            context?.rollback()
            context = nil
            container = nil
            openingError = (error is keychainError || error is CaptureLibraryError)
                ? error : CaptureLibraryError.unavailable
            storageError = openingError?.localizedDescription
            LoggerService.shared.error("Capture library unavailable; existing files kept", error: error)
        }
    }

    private func requiredContext() throws -> ModelContext {
        // A later attempt can recover after disk access or Keychain is restored.
        if context == nil { openStore() }
        guard let context else { throw openingError ?? CaptureLibraryError.unavailable }
        return context
    }

    private func currentKeyVersion() throws -> Int {
        guard let data = try keychain.data(forKey: Self.keyVersionIdentifier) else { return 1 }
        guard let version = try? JSONDecoder().decode(Int.self, from: data), version > 0 else {
            throw CaptureLibraryError.invalidKeyVersion
        }
        return version
    }

    private func getEncryptionKey(allowCreation: Bool) throws -> SymmetricKey {
        // A locked/denied Keychain is an error, not an absent key. Never replace it.
        if let keyData = try keychain.data(forKey: Self.encryptionKeyIdentifier) {
            guard keyData.count == 32 else { throw CaptureLibraryError.invalidEncryptionKey }
            return SymmetricKey(data: keyData)
        }
        guard allowCreation else { throw CaptureLibraryError.missingEncryptionKey }
        let records = try requiredContext().fetch(FetchDescriptor<CaptureRecord>())
        guard records.allSatisfy({ $0.ocrText.isEmpty }) else {
            throw CaptureLibraryError.missingEncryptionKey
        }
        let hasStoredVersion = try keychain.data(forKey: Self.keyVersionIdentifier) != nil
        let version = try currentKeyVersion()
        let newKey = SymmetricKey(size: .bits256)
        try keychain.set(newKey.withUnsafeBytes { Data($0) }, forKey: Self.encryptionKeyIdentifier)
        if !hasStoredVersion {
            try keychain.set(try JSONEncoder().encode(version), forKey: Self.keyVersionIdentifier)
        }
        return newKey
    }

    private func encrypt(_ text: String) throws -> (combined: Data, nonce: Data) {
        let key = try getEncryptionKey(allowCreation: true)
        let sealedBox = try AES.GCM.seal(Data(text.utf8), using: key)
        guard let combined = sealedBox.combined else {
            throw keychainError.unexpectedStatus(errSecInternalError)
        }
        return (combined, Data(sealedBox.nonce.withUnsafeBytes { $0 }))
    }

    private func decrypt(_ combined: Data) throws -> String {
        let key = try getEncryptionKey(allowCreation: false)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        var decryptedData = try AES.GCM.open(sealedBox, using: key)
        defer { decryptedData.resetBytes(in: 0..<decryptedData.count) }
        return String(decoding: decryptedData, as: UTF8.self)
    }

    /// Earlier versions could autosave their plaintext cache. Keep the old field
    /// in the schema, authenticate/recover its text, then clear it transactionally.
    /// This is logical removal, not secure erasure of old SQLite pages or backups.
    private func migrateLegacyPlaintext(in context: ModelContext) throws {
        let records = try context.fetch(FetchDescriptor<CaptureRecord>())
        var changed = false
        for record in records {
            guard let legacyText = record.decryptedocrText else { continue }
            if record.ocrText.isEmpty {
                let version = try currentKeyVersion()
                let (ciphertext, nonce) = try encrypt(legacyText)
                record.ocrText = ciphertext
                record.ocrNonce = nonce
                record.keyVersion = version
            } else {
                // Do not throw away the recovery copy if its key is unavailable.
                _ = try decrypt(record.ocrText)
            }
            record.decryptedocrText = nil
            changed = true
        }
        if changed { try context.save() }
    }

    /// Encrypt new OCR text before insertion; the decrypted OCR cache is transient.
    public func save(_ record: CaptureRecord) throws {
        do {
            let context = try requiredContext()
            if let plaintext = record.decryptedOcrText, record.ocrText.isEmpty {
                let version = try currentKeyVersion()
                let (ciphertext, nonce) = try encrypt(plaintext)
                record.ocrText = ciphertext
                record.ocrNonce = nonce
                record.keyVersion = version
            }
            record.decryptedocrText = nil
            context.insert(record)
            try context.save()
            refreshRecent()
        } catch {
            context?.rollback()
            storageError = error.localizedDescription
            throw error
        }
    }

    public func delete(_ record: CaptureRecord) throws {
        do {
            let context = try requiredContext()
            context.delete(record)
            try context.save()
            refreshRecent()
        } catch {
            context?.rollback()
            storageError = error.localizedDescription
            throw error
        }
    }

    public func update(_ record: CaptureRecord) throws {
        do {
            let context = try requiredContext()
            record.decryptedocrText = nil
            try context.save()
            refreshRecent()
        } catch {
            context?.rollback()
            storageError = error.localizedDescription
            throw error
        }
    }

    public func fetchAll() -> [CaptureRecord] {
        fetchRecords(FetchDescriptor<CaptureRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    public func fetch(from startDate: Date, to endDate: Date) -> [CaptureRecord] {
        fetchRecords(FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.createdAt >= startDate && $0.createdAt <= endDate },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    public func searchText(_ query: String) -> [CaptureRecord] {
        fetchAll().filter { record in
            (record.decryptedOcrText ?? "").localizedStandardContains(query) ||
            record.notes.localizedStandardContains(query) ||
            record.summary.localizedStandardContains(query) ||
            record.tags.contains { $0.localizedStandardContains(query) }
        }
    }

    public func fetchFavorites() -> [CaptureRecord] {
        fetchRecords(FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    public func fetchByTag(_ tag: String) -> [CaptureRecord] {
        fetchRecords(FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.tags.contains(tag) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    private func fetchRecords(_ descriptor: FetchDescriptor<CaptureRecord>) -> [CaptureRecord] {
        do {
            let records = try requiredContext().fetch(descriptor)
            storageError = nil
            for record in records {
                record.decryptedOcrText = nil
                guard !record.ocrText.isEmpty else { continue }
                do {
                    record.decryptedOcrText = try decrypt(record.ocrText)
                } catch {
                    // One unreadable item must not hide other readable captures.
                    storageError = error.localizedDescription
                    LoggerService.shared.warning("Could not decrypt a capture; encrypted record kept")
                }
            }
            return records
        } catch {
            storageError = error.localizedDescription
            LoggerService.shared.error("Could not read the capture library", error: error)
            return []
        }
    }

    private func refreshRecent() {
        recentCaptures = Array(fetchAll().prefix(50))
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
    
    /// Delete all captures only for an explicit reset, without requiring decryption.
    public func deleteAll() throws {
        do {
            let context = try requiredContext()
            let all = try context.fetch(FetchDescriptor<CaptureRecord>())
            for record in all { context.delete(record) }
            try context.save()
            recentCaptures = []
            storageError = nil
        } catch {
            context?.rollback()
            storageError = error.localizedDescription
            throw error
        }
    }

    public var totalCount: Int {
        guard let context else { return 0 }
        return (try? context.fetchCount(FetchDescriptor<CaptureRecord>())) ?? 0
    }

    public var totalFileSize: Int64 {
        fetchAll().reduce(0) { $0 + $1.fileSize }
    }
}

// MARK: - Keychain Service (Standalone Helper)
public final class Keychain: CaptureKeyStoring {
    
    public func set(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        // Creating an encryption key must not overwrite an item that appeared
        // between lookup and insertion (for example in another running instance).
        guard status == errSecSuccess else { throw keychainError(status) }
    }

    public func data(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw keychainError(status) }
        guard let data = result as? Data else { throw keychainError(errSecDecode) }
        return data
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
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
                return "Unlock your login keychain and allow Textractor Pro access, then try again. Existing library records and keys have been kept."
            }
            return "The capture library could not access Keychain (status \(status)). Existing records and keys have been kept."
        }
    }
}