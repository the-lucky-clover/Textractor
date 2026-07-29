import Foundation

/// Heuristic success detector for English-only OCR passes. Vision can return
/// observations that the user can't actually use:
///
///   • empty / whitespace / punctuation-only strings
///   • random glyph soup when no text was on screen
///   • extremely low-confidence noise every box around text
///   • non-Latin residue (CJK, Cyrillic, Arabic) that the recovery stack
///     surfaced because there was no real English text
///
/// For the English-only MVP we say "extraction succeeded" only when:
///
///   • `0` raw observations                                      → fail (no text)
///   • joined text under `5` printable chars                     → fail (too short)
///   • printable-character count under `5`                       → fail (empty)
///   • average Vision confidence under `0.20`                    → fail (sand)
///   • alphabetics ratio (letters / letters+digits) below `0.55` → fail (gibberish,
///                                                                    numbers-only)
///   • non-Latin letters are more than `20%` of all letters      → fail (mixed
///                                                                    script spillover)
///   • fewer than `3` "word-like" tokens                         → fail (no real
///                                                                    English strings)
///
/// Importantly, this only inspects the *result*. The actual OCR retry
/// escalation happens inside `OCRService.recognizeText(in:weirdness:)` — this
/// check sits on top of the already-self-healing pipeline and decides whether
/// to ship the text to the pasteboard or open the recovery toast.
public enum EnglishSuccessDetector {

    public struct Verdict: Equatable, Sendable {
        public let success: Bool
        public let reason: String?

        public static func ok() -> Verdict { Verdict(success: true, reason: nil) }
        public static func fail(_ why: String) -> Verdict { Verdict(success: false, reason: why) }
        public static let empty = Verdict.fail("OCR returned no text")
    }

    public static func judge(_ result: OCRResult, preferredLanguage: String = "") -> Verdict {
        guard !result.isEmpty else { return .empty }

        // 1) Average confidence gate. Vision's "sand" output clusters around
        //    0.0–0.15; anything real is at least 0.30. We pick 0.20 so
        //    low-contrast / low-DPI captures still pass.
        if result.averageConfidence < 0.20 {
            return .fail("low OCR confidence")
        }

        // 2) Joined-text shape gate.
        let text = result.joinedText
        if text.count < 5 {
            return .fail("OCR text is too short")
        }

        // Count character classes by walking unicode scalars.
        var alphabetics = 0
        var latinLetters = 0
        var nonLatinLetters = 0
        var digits = 0
        var printables = 0
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // Token-boundary whitespace.
            if v == 0x20 || v == 0x09 || v == 0x0A || v == 0x0D {
                flush()
                continue
            }
            // ASCII punctuation that splits tokens without becoming part of one.
            if v == 0x2C || v == 0x2E || v == 0x21 || v == 0x3F
                || v == 0x3A || v == 0x3B || v == 0x28 || v == 0x29
                || v == 0x5B || v == 0x5D || v == 0x7B || v == 0x7D
                || v == 0x22 || v == 0x27 || v == 0x60 {
                flush()
                continue
            }

            printables += 1
            if (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) {
                alphabetics += 1
                latinLetters += 1
                current.unicodeScalars.append(scalar)
            } else if v >= 0x30 && v <= 0x39 {
                digits += 1
                current.unicodeScalars.append(scalar)
            } else {
                // Accented Latin (U+00C0…U+024F), smart quotes / em-dash
                // count as Latin letters; everything else (CJK, Cyrillic,
                // Arabic, Hebrew, etc.) counts as non-Latin.
                let isLatinExtended = (v >= 0x00C0 && v <= 0x024F)
                let isNeutralPunctuationLike = v == 0x2019 || v == 0x201C
                    || v == 0x201D || v == 0x2018 || v == 0x2014 || v == 0x2013
                if isLatinExtended || isNeutralPunctuationLike {
                    if isLatinExtended { alphabetics += 1; latinLetters += 1 }
                    current.unicodeScalars.append(scalar)
                } else if CharacterSet.letters.contains(scalar) {
                    alphabetics += 1
                    nonLatinLetters += 1
                    current.unicodeScalars.append(scalar)
                } else {
                    // misc symbol / currency / arrow → keep token continuity
                    // but don't bump letter/digit counts.
                    current.unicodeScalars.append(scalar)
                }
            }
        }
        flush()

        if printables < 5 {
            return .fail("OCR text has no printable characters")
        }

        // 4) Alphabetic dominance.
        let totalChars = alphabetics + digits
        if totalChars > 0 {
            let letterRatio = Double(alphabetics) / Double(totalChars)
            if letterRatio < 0.55 {
                return .fail("OCR text is mostly numbers / symbols")
            }
        }

        // 5) Script gate. Only enforce the non-Latin ratio when the user has
        //    explicitly chosen English (or an English-first locale). For
        //    Automatic or any non-English language, trust the OCR engine's
        //    language selection and accept the result as long as the other
        //    gates pass.
        let lang = preferredLanguage.lowercased()
        let isEnglish = lang.isEmpty || lang == "en" || lang.hasPrefix("en-")
        if isEnglish {
            let letters = latinLetters + nonLatinLetters
            if letters > 0 {
                let nonLatinRatio = Double(nonLatinLetters) / Double(letters)
                if nonLatinRatio > 0.20 {
                    return .fail("OCR returned non-Latin characters")
                }
            }
        }

        // 6) Word-count gate.
        let wordLike = tokens.filter { $0.count >= 2 }
        if wordLike.count < 3 {
            return .fail("OCR did not find enough readable words")
        }

        return .ok()
    }
}
