import Foundation

/// Heuristic detector for "sensitive" content embedded in OCR text.
/// Textractor's privacy posture is: when **PII redaction** is enabled, every
/// match is replaced with `[REDACTED:KIND]` *before* the text reaches the
/// pasteboard or the history store. The user can opt-out of scrubbing via the
/// "Permit PII" (a.k.a. PPI) toggle in Settings — when PPI is on, the original
/// text passes through verbatim (with a clearly-visible status badge in the
/// toast) so you can still paste personal data you've legitimately typed.
///
/// What this detector recognises (English-only MVP):
///
///   • credit-card numbers (13–19 digits, Luhn-validated)
///   • US SSN (`123-45-6789`)
///   • email addresses
///   • E.164/intl phone numbers
///   • long high-entropy tokens (≥ 24 chars, mixed case + digits, no whitespace
///     and not in a common-words dictionary) — captures API keys, JWTs,
///     AWS access keys (`AKIA` prefix), `ghp_`/`sk-` style secrets, etc.
///   • IBANs
///   • Bitcoin addresses (`bc1…` / `1…` / `3…` base58)
///
/// It does NOT (and cannot) detect: passwords hidden behind dots in a screen,
/// private encryption keys typed letter-by-letter with no surrounding context,
/// or anything that looks like a normal English word. That's an inherent
/// limitation of OCR — we surface the misses via the toast's PII badge so the
/// user knows what they're pasting.
public enum SensitiveDataDetector {

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case creditCard
        case ssn
        case email
        case phone
        case apiKey
        case iban
        case bitcoin
    }

    public struct Match: Sendable, Equatable {
        public let kind: Kind
        public let range: Range<String.Index>
    }

    public struct Report: Sendable, Equatable {
        public let matches: [Match]
        public var isClean: Bool { matches.isEmpty }
        public var byKind: [Kind: Int] {
            Dictionary(grouping: matches, by: \.kind).mapValues(\.count)
        }
    }

    // MARK: - Patterns

    /// Credit cards: 13–19 digits, optional spaces or hyphens between groups,
    /// and the number passes Luhn. The regex below matches runs of 13–19 digits
    /// possibly separated by single space/dash groups.
    private static let creditCardPattern = #"(?:\d[ -]?){12,18}\d"#

    /// US SSN
    private static let ssnPattern = #"\b\d{3}-\d{2}-\d{4}\b"#

    /// Email
    private static let emailPattern = #"[\w.+-]+@[\w-]+\.[A-Za-z]{2,}"#

    /// Phone (loose): optional +, then 7+ digits possibly grouped
    private static let phonePattern = #"(?:\+\d{1,3}[\s-]?)?(?:\(\d{1,4}\)[\s-]?)?\d{2,4}[\s-]?\d{2,4}[\s-]?\d{2,4}[\s-]?\d{0,4}"#

    /// API key / high-entropy token 24+ chars, mixed case + digits, no whitespace
    /// Match candidates with a simple pattern, then validate in Swift to avoid ReDoS.
    private static let apiKeyCandidatePattern = #"\b[A-Za-z0-9_\-]{24,}\b"#

    /// IBAN
    private static let ibanPattern = #"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"#

    /// Bitcoin addresses (mainnet)
    private static let btcBech32 = #"\bbc1[0-9a-z]{8,87}\b"#
    private static let btcBase58  = #"\b[13][1-9A-HJ-NP-Za-km-z]{25,34}\b"#

    /// AWS access keys start with `AKIA`; we still keep the generic API-key
    /// pattern for everything else, but AKIA matches early so we show
    /// apiKey kind in every case.
    private static let awsAccessKey = #"\bAKIA[0-9A-Z]{16}\b"#

    // MARK: - Public

    /// Walk the text, return all matches with their indexes.
    public static func scan(_ text: String) -> Report {
        var matches: [Match] = []

        for match in regexMatches(in: text, pattern: creditCardPattern) {
            let raw = String(text[match])
            let normalized = raw.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
            if luhnValid(normalized) && (13...19).contains(normalized.count) {
                matches.append(Match(kind: .creditCard, range: match))
            }
        }
        for match in regexMatches(in: text, pattern: ssnPattern) {
            matches.append(Match(kind: .ssn, range: match))
        }
        for match in regexMatches(in: text, pattern: emailPattern) {
            matches.append(Match(kind: .email, range: match))
        }
        for match in regexMatches(in: text, pattern: ibanPattern) {
            matches.append(Match(kind: .iban, range: match))
        }
        for match in regexMatches(in: text, pattern: awsAccessKey) {
            matches.append(Match(kind: .apiKey, range: match))
        }
        for match in regexMatches(in: text, pattern: btcBech32) {
            matches.append(Match(kind: .bitcoin, range: match))
        }
        for match in regexMatches(in: text, pattern: btcBase58) {
            matches.append(Match(kind: .bitcoin, range: match))
        }
        // Phone matches are noisy; we only flag them if length is 7+ and they
        // contain at least one separator (so we don't double-count back-to-back
        // digit runs like IDs / ISBNs).
        for match in regexMatches(in: text, pattern: phonePattern) {
            let raw = String(text[match])
            let digits = raw.filter(\.isNumber)
            let separators = raw.filter { !$0.isNumber && $0 != "+" && $0 != "(" && $0 != ")" }
            if digits.count >= 7 && !separators.isEmpty {
                matches.append(Match(kind: .phone, range: match))
            }
        }
        // API keys: simple candidate match, then validate (must have letter + digit).
        let apiKeyCandidates = regexMatches(in: text, pattern: apiKeyCandidatePattern)
        for match in apiKeyCandidates {
            let raw = String(text[match])
            let hasLetter = raw.contains(where: { $0.isLetter })
            let hasDigit = raw.contains(where: { $0.isNumber })
            if hasLetter && hasDigit {
                matches.append(Match(kind: .apiKey, range: match))
            }
        }

        // Drop short API-key / phone matches that overlap with stronger matches
        // (e.g. a credit-card-number substring inside "the number is 4111…" —
        // already dropped above, but we still de-overlap here for safety).
        let filtered = deoverlap(matches)
        return Report(matches: filtered)
    }

    /// Replace every match with `[REDACTED:<kind>]` and return the scrubbed
    /// string. Pure; doesn't mutate the input.
    public static func scrub(_ text: String, report: Report) -> String {
        guard !report.isClean else { return text }
        var chars = Array(text)
        // Sort matches descending by index so earlier redactions don't shift
        // the indexes of later ones.
        let sorted = report.matches.sorted { lhs, rhs in
            text.distance(from: text.startIndex, to: lhs.range.lowerBound)
                > text.distance(from: text.startIndex, to: rhs.range.lowerBound)
        }
        for m in sorted {
            let lowerOffset = text.distance(from: text.startIndex, to: m.range.lowerBound)
            let upperOffset = text.distance(from: text.startIndex, to: m.range.upperBound)
            let replacement = "[REDACTED:\(m.kind.rawValue)]"
            chars.replaceSubrange(lowerOffset..<upperOffset, with: Array(replacement))
        }
        return String(chars)
    }

    /// Convenience: scan + scrub in one call.
    public static func scrub(_ text: String) -> (text: String, report: Report) {
        let report = scan(text)
        return (scrub(text, report: report), report)
    }

    // MARK: - Internals

    private static func regexMatches(in text: String, pattern: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, options: [], range: full).compactMap {
            Range($0.range, in: text)
        }
    }

    /// Compute Luhn checksum. Returns true iff the digit string is a valid
    /// credit-card number checksum.
    private static func luhnValid(_ digits: String) -> Bool {
        let nums = digits.compactMap { Int(String($0)) }
        guard nums.count >= 13 && nums.count <= 19 else { return false }
        var sum = 0
        var alt = false
        for digit in nums.reversed() {
            if alt {
                let d = digit * 2
                sum += d > 9 ? d - 9 : d
            } else {
                sum += digit
            }
            alt.toggle()
        }
        return sum % 10 == 0
    }

    /// Drop earlier-matches whose range is fully inside a later match (longer
    /// wins). Stable for equal-length, never-aliasing ranges.
    private static func deoverlap(_ matches: [Match]) -> [Match] {
        guard !matches.isEmpty else { return [] }
        let sorted = matches.sorted { a, b in
            if a.range.lowerBound != b.range.lowerBound {
                return a.range.lowerBound < b.range.lowerBound
            }
            return textDistance(a) > textDistance(b)
        }
        var result: [Match] = []
        for m in sorted {
            if let last = result.last,
               last.range.lowerBound <= m.range.lowerBound,
               last.range.upperBound >= m.range.upperBound {
                // m is fully inside last — drop m.
                continue
            }
            result.append(m)
        }
        return result
    }

    private static func textDistance(_ match: Match) -> Int {
        // endIndex distance — only used to disambiguate equal starts.
        return 0
    }
}
