import Foundation
import AppKit
import NaturalLanguage

/// On-device translation using Apple's `NLLanguageRecognizer` + `MLModel`
/// (or system translation if available). Snip-to-translate: after OCR,
/// translate the recognized text to the user's chosen target language.
/// Everything runs on-device, nothing leaves the Mac.
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

        // For now, use a placeholder - in production this would use
        // Apple's Translation framework (macOS 14+) or a local model
        return "[Translation to \(targetCode) would appear here]\n\(text)"
    }

    /// Detect the language of a string using NLLanguageRecognizer.
    /// Returns the BCP-17 code (e.g. "en", "es") or nil if detection fails.
    public func detectLanguageCode(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
