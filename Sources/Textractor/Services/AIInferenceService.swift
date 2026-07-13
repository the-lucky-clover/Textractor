import Foundation
import NaturalLanguage

/// `AIInferenceService` runs entirely on-device via Apple's NaturalLanguage
/// framework. It cleans OCR noise, infers sentiment, detects language, and
/// extracts keywords. Privacy-first.
public final class AIInferenceService {

    public static let shared = AIInferenceService()

    // MARK: - Public types

    public struct Analysis: Sendable, Equatable {
        public let cleanedText: String
        public let sentiment: Sentiment
        public let language: String?
        public let keywords: [String]
        public let entities: [Entity]
        public let tokens: Int

        public init(
            cleanedText: String,
            sentiment: Sentiment,
            language: String?,
            keywords: [String],
            entities: [Entity],
            tokens: Int
        ) {
            self.cleanedText = cleanedText
            self.sentiment = sentiment
            self.language = language
            self.keywords = keywords
            self.entities = entities
            self.tokens = tokens
        }
    }

    public enum Sentiment: String, Sendable, Codable, CaseIterable {
        case positive
        case neutral
        case negative
        case mixed

        public var label: String {
            switch self {
            case .positive: return "Positive"
            case .neutral:  return "Neutral"
            case .negative: return "Negative"
            case .mixed:    return "Mixed"
            }
        }

        public static func from(score: Double) -> Sentiment {
            if score >= 0.20  { return .positive }
            if score <= -0.20 { return .negative }
            return .neutral
        }

        public var colorHint: String {  // textual hint the UI maps to a concrete color
            switch self {
            case .positive: return "lime"
            case .neutral:  return "cyan"
            case .negative: return "red"
            case .mixed:    return "violet"
            }
        }
    }

    public enum Entity: Sendable, Equatable {
        case url(String)
        case email(String)
        case phone(String)
        case hashtag(String)
        case mention(String)
    }

    // MARK: - Init

    private init() {}

    // MARK: - Public

    public func analyze(_ text: String, weirdness: Double = 0.45) async -> Analysis {
        let started = Date()

        let cleaned = await Task.detached(priority: .userInitiated) {
            Self.clean(text: text, weirdness: max(0.0, min(1.0, weirdness)))
        }.value

        let sentiment = await Task.detached(priority: .userInitiated) {
            Self.sentimentScore(of: cleaned)
        }.value

        let language = await Task.detached(priority: .userInitiated) {
            Self.detectLanguage(text: cleaned)
        }.value

        let keywords = await Task.detached(priority: .userInitiated) {
            Self.extractKeywords(text: cleaned, weirdness: max(0.0, min(1.0, weirdness)))
        }.value

        let entities = await Task.detached(priority: .userInitiated) {
            Self.extractEntities(text: cleaned)
        }.value

        let tokens = cleaned.split(separator: " ", omittingEmptySubsequences: true).count

        let analysis = Analysis(
            cleanedText: cleaned,
            sentiment: sentiment,
            language: language,
            keywords: keywords,
            entities: entities,
            tokens: tokens
        )

        TelemetryService.shared.record(
            TelemetryEvent(
                kind: .aiAnalysis,
                success: true,
                latencyMs: Date().timeIntervalSince(started) * 1000,
                meta: [
                    "tokens": "\(tokens)",
                    "lang": language ?? "?",
                    "sentiment": sentiment.rawValue
                ]
            ),
            telemetryEnabled: TelemetryService.shared.isEnabled
        )

        return analysis
    }

    // MARK: - Cleaning

    /// Smart cleanup that respects the "weirdness" slider — at low values we
    /// preserve original whitespace verbatim; at high values we aggressively
    /// collapse, de-hyphenate line-breaks, and replace smart quotes.
    static func clean(text: String, weirdness: Double) -> String {
        guard !text.isEmpty else { return text }
        var s = text

        // Always: Unicode normalization, strip zero-width space & BOM.
        s = s.replacingOccurrences(of: "\u{200B}", with: "")   // zero-width space
        s = s.replacingOccurrences(of: "\u{FEFF}", with: "")  // BOM
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\t", with: " ")

        if weirdness < 0.05 {
            // Strict mode: only collapse 3+ consecutive blanks (no smart-quote
            // rewriting, no aggressive space flattening).
            s = collapseRuns(of: "\n\n\n", to: "\n\n", in: s)
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Smart-quote normalisation (always helpful on OCR text) — convert
        // curly quotes down to ASCII so downstream paste targets see stable
        // straight quotes. The earlier implementation no-op'd because it
        // replaced each glyph with itself.
        s = s.replacingOccurrences(of: "\u{201C}", with: "\"") // “
        s = s.replacingOccurrences(of: "\u{201D}", with: "\"") // ”
        s = s.replacingOccurrences(of: "\u{2018}", with: "'")  // ‘
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")  // ’

        // Strip non-printables except newlines
        s = s.unicodeScalars
            .filter { $0 == "\n" || ($0.value >= 0x20 && $0.value != 0x7F) }
            .map { Character($0) }
            .reduce(into: "", { $0.append($1) })

        // Collapse runs of spaces & blank lines with explicit regexes — easier
        // to reason about than the old doubled-token loop.
        s = collapseRuns(of: "   ", to: "  ",   in: s)
        s = collapseRuns(of: "  ",  to: " ",    in: s)
        s = collapseRuns(of: "\n\n\n", to: "\n\n", in: s)
        s = collapseRuns(of: "\n\n",   to: "\n",  in: s)

        if weirdness >= 0.5 {
            // Dehyphenate words split across lines ("extracted-\nword" → "extractedword")
            s = s.replacingOccurrences(
                of: "([A-Za-z])-\\s*\\n\\s*([A-Za-z])",
                with: "$1$2",
                options: .regularExpression
            )
            // Collapse ragged single newlines inside what looks like a paragraph.
            // Heuristic: replace 'X\nY' where neither side is blank → "X Y".
            s = s.replacingOccurrences(
                of: "([A-Za-z0-9,;:!?\\)\\]\\.\\\"'])\\n([A-Za-z0-9])",
                with: "$1 $2",
                options: .regularExpression
            )
        }

        // Trim trailing whitespace per line.
        s = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replace any run of `repeating` (two or more copies) with a single
    /// occurrence of `replacement`. Constant pattern, hot path: cache the regex.
    private static func collapseRuns(of repeating: String, to replacement: String, in text: String) -> String {
        guard repeating.count >= 1 else { return text }
        // Build the "two or more" pattern: (repeating){2,}
        let escaped = NSRegularExpression.escapedPattern(for: repeating)
        let pattern = "(?:\(escaped)){2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    // MARK: - Sentiment

    static func sentimentScore(of text: String) -> Sentiment {
        guard !text.isEmpty else { return .neutral }
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        let raw = Double(tag?.rawValue ?? "0") ?? 0
        return Sentiment.from(score: raw)
    }

    static func detectLanguage(text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    // MARK: - Keywords

    static func extractKeywords(text: String, weirdness: Double) -> [String] {
        let minLength = weirdness >= 0.5 ? 2 : 3
        let wantNounsOnly = weirdness < 0.5

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var counts: [String: Int] = [:]
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let token = text[range]
            let isNoun = tag == .noun
            if token.count < minLength { return true }
            if wantNounsOnly && !isNoun { return true }
            let lower = token.lowercased()
            counts[lower, default: 0] += 1
            return true
        }

        let sorted = counts
            .filter { $0.value >= 2 || weirdness >= 0.7 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(12)
            .map(\.key)

        return Array(sorted)
    }

    // MARK: - Entities (regex-based — fast and good enough for OCR passthrough)

    static func extractEntities(text: String) -> [Entity] {
        var hits: [Entity] = []

        let urlPattern = #"(https?://[^\s)]+|www\.[^\s)]+)"#
        let emailPattern = #"[\w.+-]+@[\w-]+\.[\w.-]+"#
        let phonePattern = #"(?:\+?\d[\d\s().-]{7,})"#
        let hashtagPattern = #"#[A-Za-z0-9_]+"#
        let mentionPattern = #"@[A-Za-z0-9_]+"#

        hits += matches(in: text, pattern: urlPattern,     make: Entity.url)
        hits += matches(in: text, pattern: emailPattern,   make: Entity.email)
        hits += matches(in: text, pattern: phonePattern,   make: Entity.phone)
        hits += matches(in: text, pattern: hashtagPattern, make: Entity.hashtag)
        hits += matches(in: text, pattern: mentionPattern, make: Entity.mention)
        return hits
    }

    private static func matches(in text: String, pattern: String, make: (String) -> Entity) -> [Entity] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).map { m in
            make(ns.substring(with: m.range))
        }
    }
}
