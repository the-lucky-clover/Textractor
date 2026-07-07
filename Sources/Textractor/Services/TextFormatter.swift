import Foundation
import AppKit

/// `TextFormatter` produces an `NSAttributedString` with cyberpunk-typography
/// styling so paste targets receive both `.string` and `.rtf` representations.
public enum TextFormatter {

    // MARK: - Public

    /// Build a rich-text version of cleaned OCR text. `weirdness` tweaks
    /// header detection aggressiveness and bullet normalisation.
    public static func attributed(
        from text: String,
        analysis: AIInferenceService.Analysis? = nil,
        weirdness: Double = 0.45
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString()

        let pStyle = NSMutableParagraphStyle()
        pStyle.lineHeightMultiple = 1.18
        pStyle.alignment = .natural
        pStyle.paragraphSpacing = 6
        pStyle.lineSpacing = 2

        let bodyFont: NSFont = roundedFont(size: 13, weight: .regular)
        let monoFont: NSFont = mono(size: 12, weight: .medium)

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: pStyle,
            .kern: 0.15
        ]

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Detect if first line is a banner / title (≤ 5 words, no terminal punctuation)
        if let first = lines.first,
           first.count <= 60,
           !(first.last?.isPunctuation ?? true),
           first.split(separator: " ").count <= 7 {
            let title = NSAttributedString(
                string: first + "\n\n",
                attributes: [
                    .font: roundedFont(size: 19, weight: .heavy),
                    .foregroundColor: NSColor.labelColor,
                    .kern: 0.5,
                    .paragraphStyle: headingParagraphStyle()
                ]
            )
            attributed.append(title)
            lines.removeFirst()
        }

        for raw in lines {
            var line = raw
            // Normalise bullet markers
            line = line
                .replacingOccurrences(of: "•", with: "• ")
                .replacingOccurrences(of: "\\s*\\*\\s+", with: " • ", options: .regularExpression)

            // Line classification
            let isBullet = line.hasPrefix("• ") || isNumbered(line)
            let isTableRow = line.contains("|") && line.dropFirst().contains("|")

            let renderer: NSMutableAttributedString
            if isTableRow {
                renderer = renderTableLine(line, baseFont: monoFont)
            } else if isBullet {
                renderer = renderBullet(line, baseFont: bodyFont, baseAttrs: baseAttrs)
            } else {
                renderer = NSMutableAttributedString(string: line.isEmpty ? "\n" : line, attributes: baseAttrs)
            }

            applyEntityHighlighting(to: renderer)
            applyKeywordHighlight(to: renderer, keywords: analysis?.keywords ?? [])

            attributed.append(renderer)
            attributed.append(NSAttributedString(string: "\n"))
        }

        return attributed
    }

    // MARK: - Internals

    private static func headingParagraphStyle() -> NSMutableParagraphStyle {
        let s = NSMutableParagraphStyle()
        s.alignment = .natural
        s.paragraphSpacingBefore = 4
        s.lineHeightMultiple = 1.05
        return s
    }

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let descriptor = NSFontDescriptor
            .preferredFontDescriptor(forTextStyle: .body)
            .withDesign(.rounded)?
            .addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])

        if let descriptor,
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }

        // Fallback path that doesn't crash
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let rounded = base.rounded()
        return rounded ?? base
    }

    private static func mono(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func isNumbered(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let first = t.first, first.isNumber else { return false }
        return t.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
    }

    private static func renderTableLine(_ line: String, baseFont: NSFont) -> NSMutableAttributedString {
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let joined = cells.joined(separator: "    ")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ]
        return NSMutableAttributedString(string: joined, attributes: attrs)
    }

    private static func renderBullet(
        _ line: String,
        baseFont: NSFont,
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSMutableAttributedString {
        let pStyle = (baseAttrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
        pStyle?.headIndent = 14
        pStyle?.firstLineHeadIndent = 0
        var attrs = baseAttrs
        attrs[.paragraphStyle] = pStyle ?? NSMutableParagraphStyle()
        attrs[.font] = baseFont
        return NSMutableAttributedString(string: line, attributes: attrs)
    }

    private static func applyEntityHighlighting(to renderer: NSMutableAttributedString) {
        let ns = renderer.string as NSString
        let pattern = #"https?://[^\s)]+|www\.[^\s)]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        regex.enumerateMatches(in: renderer.string, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let r = match?.range else { return }
            renderer.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            renderer.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: r)
        }
    }

    private static func applyKeywordHighlight(to renderer: NSMutableAttributedString, keywords: [String]) {
        guard !keywords.isEmpty else { return }
        let ns = renderer.string as NSString
        for kw in keywords.prefix(8) {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: kw))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            regex.enumerateMatches(in: renderer.string, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let r = match?.range else { return }
                renderer.addAttribute(.backgroundColor, value: NSColor.systemTeal.withAlphaComponent(0.18), range: r)
                renderer.addAttribute(.font,
                    value: mono(size: 13, weight: .semibold),
                    range: r)
            }
        }
    }
}

private extension NSFont {
    func rounded() -> NSFont? {
        let descriptor = self.fontDescriptor.withDesign(.rounded)
        return descriptor.flatMap { NSFont(descriptor: $0, size: 0) }
    }
}

private extension Character {
    var isPunctuation: Bool {
        switch self {
        case ".", ",", ";", ":", "!", "?", "—", "-", "/", "\\": return true
        default: return false
        }
    }
}
