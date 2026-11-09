import XCTest
import SwiftData
import Security
@testable import Textractor

private final class MemoryCaptureKeychain: CaptureKeyStoring {
    var values: [String: Data] = [:]
    var deniedStatus: OSStatus?
    private(set) var writes = 0

    func data(forKey key: String) throws -> Data? {
        if let deniedStatus { throw keychainError(deniedStatus) }
        return values[key]
    }

    func set(_ data: Data, forKey key: String) throws {
        if let deniedStatus { throw keychainError(deniedStatus) }
        guard values[key] == nil else { throw keychainError(errSecDuplicateItem) }
        writes += 1
        values[key] = data
    }
}

@MainActor
final class CaptureStoreSafetyTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextractorCaptureSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func record(_ text: String, date: Date = Date()) -> CaptureRecord {
        CaptureRecord(createdAt: date, mode: "crosshair", origin: "file", rect: .zero,
                      filePath: "/test-capture.png", ocrText: text)
    }

    func testDecryptedTextIsTransientAcrossSaveAndReopen() throws {
        let directory = try temporaryDirectory()
        let keys = MemoryCaptureKeychain()
        let privateText = "PRIVATE-OCR-\(UUID().uuidString)-must-not-enter-the-SwiftData-cache-field"
        try autoreleasepool {
            let store = CaptureStore(directory: directory, keychain: keys)
            XCTAssertTrue(store.isAvailable)
            let capture = record(privateText)
            try store.save(capture)
            let loaded = try XCTUnwrap(store.fetchAll().first)
            XCTAssertEqual(loaded.decryptedOcrText, privateText)
            XCTAssertNil(loaded.decryptedocrText)
            loaded.isFavorite = true
            try store.update(loaded)
            // Force an unrelated save after a read, reproducing the former leak.
            try XCTUnwrap(store.context).save()
        }

        let reopened = CaptureStore(directory: directory, keychain: keys)
        let raw = try XCTUnwrap(reopened.context).fetch(FetchDescriptor<CaptureRecord>())
        XCTAssertEqual(raw.count, 1)
        XCTAssertNil(raw.first?.decryptedOcrText, "A new context must not load the in-memory cache")
        XCTAssertNil(raw.first?.decryptedocrText, "The legacy persisted cache must remain empty")
        XCTAssertTrue(try XCTUnwrap(raw.first).isFavorite)
        XCTAssertEqual(reopened.fetchAll().first?.decryptedOcrText, privateText)
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(bytes.range(of: Data(privateText.utf8)), "New database/WAL contains decrypted OCR: \(file.lastPathComponent)")
        }
    }

    func testLegacyPlaintextCacheIsClearedWithoutChangingCiphertext() throws {
        let directory = try temporaryDirectory()
        let keys = MemoryCaptureKeychain()
        let text = "Legacy persisted cache"
        var ciphertext = Data()
        try autoreleasepool {
            let previous = CaptureStore(directory: directory, keychain: keys)
            let capture = record(text)
            try previous.save(capture)
            ciphertext = capture.ocrText
            // Seed exactly the original stored field, as an older build could autosave it.
            capture.decryptedocrText = text
            try XCTUnwrap(previous.context).save()
        }

        let migrated = CaptureStore(directory: directory, keychain: keys)
        XCTAssertNil(migrated.storageError)
        let loaded = try XCTUnwrap(migrated.fetchAll().first)
        XCTAssertEqual(loaded.decryptedOcrText, text)
        XCTAssertNil(loaded.decryptedocrText)
        XCTAssertEqual(loaded.ocrText, ciphertext)
        // Confirm the migration was persisted, not just cleared on one returned object.
        let reopened = CaptureStore(directory: directory, keychain: keys)
        let raw = try XCTUnwrap(reopened.context).fetch(FetchDescriptor<CaptureRecord>())
        XCTAssertNil(raw.first?.decryptedocrText)
        XCTAssertEqual(raw.first?.ocrText, ciphertext)
    }

    func testLegacyCacheWithoutCiphertextIsEncryptedBeforeClearing() throws {
        let directory = try temporaryDirectory()
        let keys = MemoryCaptureKeychain()
        try autoreleasepool {
            let previous = CaptureStore(directory: directory, keychain: keys)
            let capture = record("")
            capture.decryptedocrText = "Recover this old field"
            let context = try XCTUnwrap(previous.context)
            context.insert(capture)
            try context.save()
        }
        let migrated = CaptureStore(directory: directory, keychain: keys)
        XCTAssertTrue(migrated.isAvailable)
        let loaded = try XCTUnwrap(migrated.fetchAll().first)
        XCTAssertEqual(loaded.decryptedOcrText, "Recover this old field")
        XCTAssertNil(loaded.decryptedocrText)
        XCTAssertFalse(loaded.ocrText.isEmpty)
    }

    func testLockedKeychainDoesNotReplaceKeyAndCanRecover() throws {
        let directory = try temporaryDirectory()
        let keys = MemoryCaptureKeychain()
        let store = CaptureStore(directory: directory, keychain: keys)
        try store.save(record("Original encrypted text"))
        let originalKeys = keys.values
        let writes = keys.writes
        keys.deniedStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.save(record("Must not save while locked")))
        XCTAssertEqual(keys.values, originalKeys)
        XCTAssertEqual(keys.writes, writes)
        XCTAssertEqual(store.totalCount, 1)
        XCTAssertTrue(store.storageError?.contains("Unlock your login keychain") == true)
        keys.deniedStatus = nil
        try store.save(record("New text after unlock"))
        XCTAssertEqual(store.totalCount, 2)
        XCTAssertEqual(keys.values, originalKeys)
        XCTAssertEqual(Set(store.fetchAll().compactMap(\.decryptedOcrText)),
                       Set(["Original encrypted text", "New text after unlock"]))
    }

    func testExistingVersionMetadataIsReusedWhenEmptyLibraryCreatesItsKey() throws {
        let directory = try temporaryDirectory()
        let keys = MemoryCaptureKeychain()
        let versionData = try JSONEncoder().encode(7)
        keys.values[CaptureStore.keyVersionIdentifier] = versionData
        let store = CaptureStore(directory: directory, keychain: keys)
        try store.save(record("First capture with retained version metadata"))
        XCTAssertEqual(store.totalCount, 1)
        XCTAssertEqual(keys.writes, 1, "Only the missing encryption key should be created")
        XCTAssertEqual(keys.values[CaptureStore.keyVersionIdentifier], versionData)
        let capture = try XCTUnwrap(store.fetchAll().first)
        XCTAssertEqual(capture.keyVersion, 7)
        XCTAssertEqual(capture.decryptedOcrText, "First capture with retained version metadata")
    }

    func testMissingKeyDoesNotGenerateReplacementForEncryptedRecords() throws {
        let directory = try temporaryDirectory()
        let keys = MemoryCaptureKeychain()
        let store = CaptureStore(directory: directory, keychain: keys)
        let original = record("Keep original ciphertext")
        try store.save(original)
        let ciphertext = original.ocrText
        keys.values.removeValue(forKey: CaptureStore.encryptionKeyIdentifier)
        let writes = keys.writes
        XCTAssertThrowsError(try store.save(record("Cannot save without the old key"))) { error in
            guard let libraryError = error as? CaptureLibraryError,
                  case .missingEncryptionKey = libraryError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(keys.writes, writes)
        XCTAssertNil(keys.values[CaptureStore.encryptionKeyIdentifier])
        XCTAssertEqual(store.totalCount, 1)
        XCTAssertEqual(original.ocrText, ciphertext)
    }

    func testUnavailableStorageDoesNotCrashOrReplaceOriginalFile() throws {
        let directory = try temporaryDirectory()
        let unavailable = directory.appendingPathComponent("blocked-directory")
        let original = Data("Existing file must survive library open and save failure".utf8)
        try original.write(to: unavailable)
        let keys = MemoryCaptureKeychain()
        let store = CaptureStore(directory: unavailable, keychain: keys)
        XCTAssertFalse(store.isAvailable)
        XCTAssertNotNil(store.storageError)
        XCTAssertThrowsError(try store.save(record("No false persistence success")))
        XCTAssertEqual(try Data(contentsOf: unavailable), original)
        XCTAssertEqual(keys.writes, 0)
        // Restore only this test fixture, then exercise recovery on the same store.
        try FileManager.default.removeItem(at: unavailable)
        try store.save(record("Recovered storage"))
        XCTAssertTrue(store.isAvailable)
        XCTAssertEqual(store.fetchAll().first?.decryptedOcrText, "Recovered storage")
    }

    func testFailedLegacyMigrationRetainsRecoveryTextAndCiphertext() throws {
        let directory = try temporaryDirectory()
        let keys = MemoryCaptureKeychain()
        var ciphertext = Data()
        try autoreleasepool {
            let previous = CaptureStore(directory: directory, keychain: keys)
            let capture = record("Retain until the keychain is unlocked")
            try previous.save(capture)
            ciphertext = capture.ocrText
            capture.decryptedocrText = "Retain until the keychain is unlocked"
            try XCTUnwrap(previous.context).save()
        }
        let originalKeys = keys.values
        keys.deniedStatus = errSecInteractionNotAllowed
        let blocked = CaptureStore(directory: directory, keychain: keys)
        XCTAssertFalse(blocked.isAvailable)
        XCTAssertThrowsError(try blocked.save(record("Must not replace inaccessible library")))
        XCTAssertEqual(keys.values, originalKeys)
        keys.deniedStatus = nil
        XCTAssertEqual(blocked.fetchAll().first?.decryptedOcrText, "Retain until the keychain is unlocked")
        XCTAssertEqual(blocked.fetchAll().first?.ocrText, ciphertext)
    }

    func testOneUndecryptableCaptureDoesNotHideOtherReadableRecords() throws {
        let directory = try temporaryDirectory()
        let store = CaptureStore(directory: directory, keychain: MemoryCaptureKeychain())
        let valid = record("Still readable", date: Date(timeIntervalSince1970: 100))
        try store.save(valid)
        let damaged = record("Damage only this test fixture", date: Date(timeIntervalSince1970: 200))
        try store.save(damaged)
        damaged.ocrText = Data("Not a valid AES-GCM box".utf8)
        try XCTUnwrap(store.context).save()
        let records = store.fetchAll()
        XCTAssertEqual(records.count, 2)
        XCTAssertNil(records.first?.decryptedOcrText)
        XCTAssertEqual(records.last?.decryptedOcrText, "Still readable")
        XCTAssertNotNil(store.storageError)
    }
}
