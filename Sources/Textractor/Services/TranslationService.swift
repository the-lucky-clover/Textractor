import Foundation
import AppKit
import NaturalLanguage

/// Language detection and translation capability boundary.
/// No translation backend is installed; callers retain the original OCR text.
public final class TranslationService {

    public static let shared = TranslationService()

    /// Available target languages shown in Settings.
    public static let supportedTargets: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ru", "Russian"),
        ("pl", "Polish"),
        ("tr", "Turkish"),
        ("ar", "Arabic"),
        ("he", "Hebrew"),
        ("hi", "Hindi"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
        ("id", "Indonesian"),
        ("ms", "Malay"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh-Hans", "Chinese (Simplified)"),
        ("zh-Hant", "Chinese (Traditional)")
    ]

    public static let isAvailable = false

    private init() {}

    /// Translate a string to the target language code (BCP-47 like "es", "ja", "zh-Hans").
    /// Returns `nil` if translation fails or is disabled.
    public func translate(
        _ text: String,
        to targetCode: String,
        sourceCode: String? = nil
    ) async -> String? {
        guard !text.isEmpty else { return nil }
        guard !targetCode.isEmpty else { return nil }
        // Detect source if not provided
        let detected = sourceCode ?? detectLanguageCode(text) ?? "en"

        // Skip if source matches target
        if detected.lowercased() == targetCode.lowercased() { return nil }

        return nil // Never replace clipboard text with a simulated translation.
    }

    /// Detect the language of a string using NLLanguageRecognizer.
    /// Returns the BCP-17 code (e.g. "en", "es") or nil if detection fails.
    public func detectLanguageCode(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
