import Foundation

/// Confidence and text-content checks; Automatic mode accepts supported scripts.
public enum EnglishSuccessDetector {

    public struct Verdict: Equatable, Sendable {
        public let success: Bool
        public let reason: String?

        public static func ok() -> Verdict { Verdict(success: true, reason: nil) }
        public static func fail(_ why: String) -> Verdict { Verdict(success: false, reason: why) }
        public static let empty = Verdict.fail("OCR returned no text")
    }

    public static func judge(_ result: OCRResult, preferredLanguage: String = "") -> Verdict {
        let text = result.joinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, !text.isEmpty else { return .empty }
        guard result.averageConfidence >= 0.20 else { return .fail("low OCR confidence") }
        guard text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return .fail("OCR returned only punctuation")
        }
        // Short captures need stronger confidence; do not invent a three-word minimum.
        if text.count < 5 && result.averageConfidence < 0.5 { return .fail("low confidence in short text") }
        let language = preferredLanguage.lowercased()
        if language == "en" || language.hasPrefix("en-") {
            let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            let nonLatin = letters.filter { $0.value > 0x024F }
            if !letters.isEmpty, Double(nonLatin.count) / Double(letters.count) > 0.20 {
                return .fail("OCR returned non-Latin characters in English mode")
            }
        }
        return .ok()
    }
}
