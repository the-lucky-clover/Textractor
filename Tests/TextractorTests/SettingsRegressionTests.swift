import XCTest
import AppKit
@testable import Textractor

@MainActor
final class SettingsRegressionTests: XCTestCase {
    func testFreshAndResetDefaultsUseUSEnglish() throws {
        XCTAssertEqual(AppSettings().uiLanguage, "en-US")
        XCTAssertEqual(AppSettings.default.uiLanguage, "en-US")
        let suite = "com.textractor.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults, appliesSystemEffects: false)
        let state = AppState(settingsStore: store)
        XCTAssertEqual(state.settings.uiLanguage, "en-US")
        state.updateSettings { $0.uiLanguage = "fr-FR" }
        state.resetSettingsToDefaults()
        store.flushPendingPersist()
        XCTAssertEqual(SettingsStore(userDefaults: defaults, appliesSystemEffects: false).current.uiLanguage, "en-US")
    }

    func testUSEnglishAliasesAndEveryCatalogValue() {
        for alias in ["en", "en_US", "EN-us", " English ", "English (US)", "English (United States)"] {
            XCTAssertEqual(AppSettings.normalizedLanguage(alias), "en-US", alias)
        }
        for entry in AppSettings.ocrLanguageCatalog {
            XCTAssertEqual(AppSettings.normalizedLanguage(entry.code), entry.code)
        }
        XCTAssertEqual(AppSettings.normalizedLanguage("Automatic"), "")
        XCTAssertEqual(AppSettings.normalizedLanguage("unknown"), "")
    }

    func testTwentyLanguageRoundTripsAndRelaunch() throws {
        let suite = "com.textractor.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults, appliesSystemEffects: false)
        let state = AppState(settingsStore: store)
        for _ in 0..<20 {
            for code in ["fr-FR", "en_US", "", "en-GB", "en-US"] {
                state.updateSettings { $0.uiLanguage = code }
                store.flushPendingPersist()
                let reopened = SettingsStore(userDefaults: defaults, appliesSystemEffects: false)
                XCTAssertEqual(reopened.current.uiLanguage, AppSettings.normalizedLanguage(code))
                XCTAssertEqual(state.settings.uiLanguage, reopened.current.uiLanguage)
            }
        }
        XCTAssertEqual(T.s("en-US", "language"), "Language")
    }

    func testExplicitAutomaticWinsOverStaleLegacyLanguage() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.default)) as? [String: Any])
        object["uiLanguage"] = ""
        object["ocrLanguages"] = ["fr-FR"]
        let automatic = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(automatic.uiLanguage, "")
        object.removeValue(forKey: "uiLanguage")
        let migrated = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated.uiLanguage, "fr-FR")
    }

    func testNewOptionsSurviveEncoding() throws {
        var settings = AppSettings.default
        settings.additiveClipboard = true
        settings.readAloud = true
        settings.recognizeBarcodes = true
        settings.showSuccessNotifications = false
        settings.speechRate = 0.25
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.additiveClipboard)
        XCTAssertTrue(decoded.readAloud)
        XCTAssertTrue(decoded.recognizeBarcodes)
        XCTAssertFalse(decoded.showSuccessNotifications)
        XCTAssertEqual(decoded.speechRate, 0.25)
    }

    func testFormattingAndDormantTranslationPreferencesSurviveRelaunch() throws {
        let suite = "com.textractor.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults, appliesSystemEffects: false)
        store.mutate {
            $0.sourceCodeMode = true
            $0.translateAfterCapture = true
            $0.translationTargetLanguage = "ja-JP"
        }
        store.flushPendingPersist()

        let restored = SettingsStore(userDefaults: defaults, appliesSystemEffects: false).current
        XCTAssertTrue(restored.sourceCodeMode)
        XCTAssertTrue(restored.translateAfterCapture)
        XCTAssertEqual(restored.translationTargetLanguage, "ja-JP")
        XCTAssertEqual(restored.uiLanguage, "en-US")
        // Preserving an old preference does not enable an absent translator.
        XCTAssertFalse(TranslationService.isAvailable)
    }

    func testBatchPreservesRepeatedMessagesAndUndo() {
        var batch = CaptureAccumulator()
        XCTAssertTrue(batch.append("Yes"))
        XCTAssertTrue(batch.append("Yes"))
        XCTAssertEqual(batch.text, "Yes\n\nYes")
        batch.undo()
        XCTAssertEqual(batch.text, "Yes")
        batch.clear()
        XCTAssertEqual(batch.text, "")
        batch.undo()
        XCTAssertFalse(batch.append(""))
        XCTAssertFalse(batch.append(String(repeating: "a", count: CaptureAccumulator.characterLimit + 1)))
    }
}
