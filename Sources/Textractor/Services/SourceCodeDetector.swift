import Foundation
import AppKit

/// Detects whether OCR'd text looks like source code and, if so, extracts the
/// language and normalizes indentation for paste-as-fenced-code-block output.
///
/// Textractor's "Source code mode" is a feature that runs after OCR: it inspects
/// the raw text for code-like density (braces, semicolons, indentation runs),
/// identifies the most likely language by keyword heuristics, and rewrites the
/// text as a markdown fenced code block with proper indentation.
public struct SourceCodeDetector {

    public struct DetectionResult: Sendable {
        public let isCode: Bool
        public let language: String?  // e.g. "swift", "python"
        public let normalized: String  // text with proper indentation

        /// Returns the text wrapped in a fenced markdown code block if it's code,
        /// otherwise returns the original text.
        public var formatted: String {
            guard isCode, let lang = language else { return normalized }
            return "```\(lang)\n\(normalized)\n```"
        }
    }

    /// Analyze a piece of OCR'd text and return detection result.
    public static func analyze(_ text: String) -> DetectionResult {
        guard !text.isEmpty else { return DetectionResult(isCode: false, language: nil, normalized: text) }

        let metrics = computeMetrics(text)
        let isCode = shouldTreatAsCode(metrics)
        guard isCode else { return DetectionResult(isCode: false, language: nil, normalized: text) }

        let language = detectLanguage(text, metrics: metrics)
        let normalized = preserveIndentation(text)
        return DetectionResult(isCode: true, language: language, normalized: normalized)
    }

    /// Wrap text as a markdown fenced code block if source code mode is enabled.
    /// Returns the original text unchanged when the mode is off or the text isn't code.
    public static func formatIfEnabled(text: String, modeEnabled: Bool) -> String {
        guard modeEnabled else { return text }
        let result = analyze(text)
        guard result.isCode, let lang = result.language else { return text }

        return "```\(lang)\n\(result.normalized)\n```"
    }

    // MARK: - Metrics

    private struct Metrics {
        let lineCount: Int
        let symbolDensity: Double
        let hasIndentation: Bool
        let keywordHits: Int
        let hasBraces: Bool
        let hasSemicolons: Bool
        let hasPunctuation: Bool
        let indentConsistency: Double
    }

    private static func computeMetrics(_ text: String) -> Metrics {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let lineCount = lines.count
        let symbolChars = CharacterSet(charactersIn: "{}()[]<>;=+-*/%|&^!~:.,?")
        let symbolCount = text.unicodeScalars.filter { symbolChars.contains($0) }.count
        let symbolDensity = text.isEmpty ? 0 : Double(symbolCount) / Double(text.count)
        let hasIndentation = lines.contains { $0.first == " " || $0.first == "\t" }
        let keywordHits = countKeywords(in: text)
        let hasBraces = text.contains("{") && text.contains("}")
        let hasSemicolons = text.contains(";")
        let hasPunctuation = text.contains(",") || text.contains(";")
        let indentConsistency = computeIndentConsistency(lines)
        return Metrics(
            lineCount: lineCount,
            symbolDensity: symbolDensity,
            hasIndentation: hasIndentation,
            keywordHits: keywordHits,
            hasBraces: hasBraces,
            hasSemicolons: hasSemicolons,
            hasPunctuation: hasPunctuation,
            indentConsistency: indentConsistency
        )
    }

    private static func shouldTreatAsCode(_ m: Metrics) -> Bool {
        // Multi-line + code-like signals
        guard m.lineCount >= 3 else { return false }
        // Heuristic threshold: high symbol density OR (indented + braces) OR (multiple keywords)
        if m.symbolDensity > 0.08 { return true }
        if m.hasIndentation && m.hasBraces { return true }
        if m.keywordHits >= 3 { return true }
        if m.indentConsistency > 0.5 && m.hasBraces { return true }
        return false
    }

    private static func computeIndentConsistency(_ lines: [String]) -> Double {
        // Count lines that start with whitespace and look "code-like"
        let indented = lines.filter { $0.first == " " || $0.first == "\t" }
        guard !indented.isEmpty else { return 0 }
        return Double(indented.count) / Double(lines.count)
    }

    // MARK: - Keyword detection

    private static let swiftKeywords: Set<String> = [
        "func", "var", "let", "if", "else", "return", "class", "struct", "enum",
        "protocol", "extension", "import", "private", "public", "internal", "open",
        "guard", "for", "in", "while", "switch", "case", "default", "break",
        "continue", "self", "super", "init", "deinit", "static", "throws", "throw",
        "try", "catch", "do", "defer", "where", "as", "is", "true", "false", "nil"
    ]
    private static let pythonKeywords: Set<String> = [
        "def", "class", "if", "elif", "else", "return", "import", "from", "as",
        "for", "while", "in", "not", "and", "or", "True", "False", "None", "self",
        "try", "except", "finally", "raise", "with", "lambda", "pass", "break",
        "continue", "yield", "global", "nonlocal", "assert"
    ]
    private static let jsKeywords: Set<String> = [
        "function", "const", "let", "var", "if", "else", "return", "class",
        "extends", "import", "export", "from", "default", "new", "this", "super",
        "for", "while", "do", "switch", "case", "break", "continue", "try", "catch",
        "finally", "throw", "typeof", "instanceof", "true", "false", "null", "undefined"
    ]
    private static let cKeywords: Set<String> = [
        "int", "float", "double", "char", "void", "long", "short", "unsigned",
        "if", "else", "for", "while", "do", "return", "struct", "union", "enum",
        "typedef", "sizeof", "static", "const", "switch", "case", "default",
        "break", "continue", "goto", "true", "false", "NULL"
    ]
    private static let shellKeywords: Set<String> = [
        "if", "then", "fi", "else", "elif", "case", "esac", "for", "while",
        "do", "done", "in", "function", "return", "echo", "export", "local",
        "source", "true", "false"
    ]
    private static let jsonKeywords: Set<String> = []  // JSON has no keywords, but has braces
    private static let goKeywords: Set<String> = [
        "func", "var", "const", "if", "else", "return", "package", "import",
        "for", "range", "switch", "case", "default", "break", "continue",
        "go", "defer", "type", "struct", "interface", "map", "chan", "true", "false", "nil"
    ]
    private static let rustKeywords: Set<String> = [
        "fn", "let", "mut", "if", "else", "return", "struct", "enum", "trait",
        "impl", "pub", "use", "mod", "for", "while", "loop", "match", "as", "in",
        "where", "true", "false", "self", "Self", "ref", "move"
    ]
    private static let rubyKeywords: Set<String> = [
        "def", "class", "module", "if", "elsif", "else", "end", "do", "yield",
        "return", "require", "include", "extend", "attr_accessor", "true", "false", "nil"
    ]

    private static func countKeywords(in text: String) -> Int {
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var hits = 0
        let sets: [Set<String>] = [swiftKeywords, pythonKeywords, jsKeywords, cKeywords, shellKeywords, goKeywords, rustKeywords, rubyKeywords]
        for token in tokens {
            for kwSet in sets where kwSet.contains(token) {
                hits += 1
                break
            }
        }
        return hits
    }

    private static func detectLanguage(_ text: String, metrics m: Metrics) -> String? {
        let lower = text.lowercased()
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let tokenSet = Set(tokens)

        // Score each language by keyword hits
        func score(_ set: Set<String>) -> Int {
            tokenSet.intersection(set).count
        }

        let scores: [(String, Int)] = [
            ("swift", score(swiftKeywords)),
            ("python", score(pythonKeywords)),
            ("javascript", score(jsKeywords)),
            ("c", score(cKeywords)),
            ("bash", score(shellKeywords)),
            ("go", score(goKeywords)),
            ("rust", score(rustKeywords)),
            ("ruby", score(rubyKeywords))
        ]
        let best = scores.max { $0.1 < $1.1 }
        if let best, best.1 >= 2 {
            return best.0
        }
        // JSON / data fallback
        if text.first == "{" && text.last == "}" {
            return "json"
        }
        if text.contains("<?xml") || text.contains("</") {
            return "xml"
        }
        if text.contains("<!DOCTYPE html") || text.contains("<html") {
            return "html"
        }
        return nil
    }

    // MARK: - Indentation preservation

    /// Preserve indentation by converting tabs to 4 spaces and trimming trailing whitespace.
    public static func preserveIndentation(_ text: String) -> String {
        // Split into lines, replace tabs with 4 spaces, trim trailing whitespace
        let lines = text.components(separatedBy: .newlines)
        return lines
            .map { line -> String in
                let expanded = line.replacingOccurrences(of: "\t", with: "    ")
                // Trim trailing whitespace but preserve leading indentation
                let trailingTrimmed = String(expanded.reversed().drop(while: { $0 == " " }).reversed())
                return trailingTrimmed
            }
            .joined(separator: "\n")
    }
}
