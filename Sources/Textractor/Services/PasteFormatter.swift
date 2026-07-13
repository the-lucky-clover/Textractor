import Foundation

/// Pure text transforms applied to OCR output before it reaches the clipboard.
/// Kept separate from the pipeline so the rules are easy to test and reason
/// about. All functions are stateless.
public enum PasteFormatter {

    /// Apply the user's layout choice plus cleanup toggles to `text`.
    ///
    /// - Parameters:
    ///   - text: the base extracted text (already OCR- and AI-cleaned).
    ///   - tableMarkdown: a pre-built Markdown table when the capture looked
    ///     tabular, or `nil`. Only used when `layout == .reconstruct`.
    ///   - layout: original / paragraphs / reconstruct.
    ///   - deHyphenate: re-join words split by a hyphen at line ends.
    ///   - collapseBlankLines: squeeze 3+ blank lines into one.
    ///   - trimTrailingWhitespace: strip trailing spaces per line + overall.
    public static func format(
        _ text: String,
        tableMarkdown: String?,
        layout: PasteLayout,
        deHyphenate: Bool,
        collapseBlankLines: Bool,
        trimTrailingWhitespace: Bool
    ) -> String {
        // Reconstruct mode: ship the table verbatim (its alignment must not be
        // reflowed). Fall back to the standard path when there is no table.
        if layout == .reconstruct, let tableMarkdown, !tableMarkdown.isEmpty {
            return tableMarkdown
        }

        var result = text

        if deHyphenate {
            result = self.deHyphenate(result)
        }

        switch layout {
        case .paragraphs:
            result = flattenToParagraphs(result)
        case .original, .reconstruct:
            break
        }

        if trimTrailingWhitespace {
            result = trimTrailing(result)
        }

        if collapseBlankLines {
            result = collapseBlanks(result)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Individual transforms

    /// Re-join words hyphenated across a line break: "inter-\nnational" →
    /// "international". Only collapses when a lowercase letter precedes the
    /// hyphen and a letter follows on the next line (avoids eating real hyphens).
    public static func deHyphenate(_ text: String) -> String {
        let pattern = "([A-Za-z])-\\n[ \\t]*([a-z])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1$2")
    }

    /// Merge soft-wrapped lines into flowing paragraphs. A blank line starts a
    /// new paragraph; single line breaks within a block become spaces.
    public static func flattenToParagraphs(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        let paragraphs: [String] = blocks.map { block in
            block
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        }
        return paragraphs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Strip trailing whitespace from every line.
    public static func trimTrailing(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var s = String(line)
                while let last = s.last, last == " " || last == "\t" { s.removeLast() }
                return s
            }
            .joined(separator: "\n")
    }

    /// Collapse runs of 3+ newlines (2+ blank lines) into a single blank line.
    public static func collapseBlanks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\n{3,}") else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n\n")
    }
}
