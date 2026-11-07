import Foundation

enum TextKind: String, Codable, CaseIterable { case message, timestamp, interface }
enum MessageSide: String, Codable, CaseIterable { case unassigned, incoming, outgoing }

struct SourceScreenshot: Identifiable, Codable, Equatable {
    var id: UUID
    var filename: String
    var relativePath: String
    var sha256: String
    var importedAt: Date
}

struct TranscriptBlock: Identifiable, Codable, Equatable {
    var id = UUID()
    var sourceID: UUID
    var originalText: String
    var editedText: String?
    var rect: CGRect
    var confidence: Float
    var kind: TextKind = .message
    // Speaker identity and date are never guessed from bubble color or screen position.
    var side: MessageSide = .unassigned
    var speaker = ""
    var userTimestamp = ""
    var excluded = false
    var exclusionReason = ""
    var text: String { editedText ?? originalText }
    var isEdited: Bool { editedText != nil && editedText != originalText }
}

struct ArchiveChange: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var blockID: UUID?
    var action: String
    var before: String
    var after: String
}

struct ConversationArchive: Codable {
    var schemaVersion = 1
    var title = "Conversation packet"
    var createdAt = Date()
    var sources: [SourceScreenshot] = []
    var blocks: [TranscriptBlock] = []
    var changes: [ArchiveChange] = []
    var reviewedOverlaps: [String] = []

    mutating func replace(_ block: TranscriptBlock) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let old = blocks[index]
        guard old != block else { return }
        let encoder = JSONEncoder()
        changes.append(ArchiveChange(blockID: block.id, action: "review/edit",
            before: (try? String(data: encoder.encode(old), encoding: .utf8)) ?? "",
            after: (try? String(data: encoder.encode(block), encoding: .utf8)) ?? ""))
        blocks[index] = block
    }
}

struct OverlapProposal: Identifiable {
    var id: String { laterIDs.map(\.uuidString).joined() }
    var earlierIDs: [UUID]
    var laterIDs: [UUID]
    var similarity: Double
}

enum ConversationLogic {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func editDistance(_ left: String, _ right: String) -> Int {
        let a = Array(left), b = Array(right)
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var next = [i + 1]
            for (j, y) in b.enumerated() {
                next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + (x == y ? 0 : 1)))
            }
            row = next
        }
        return row[b.count]
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let a = normalized(String(a.prefix(1000))), b = normalized(String(b.prefix(1000)))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        guard abs(a.count - b.count) <= max(a.count, b.count) / 10 else { return 0 }
        // Amounts, dates and phone numbers are not interchangeable fuzzy matches.
        let numbers: (String) -> [String] = { $0.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty } }
        guard numbers(a) == numbers(b) else { return 0 }
        return 1 - Double(editDistance(a, b)) / Double(max(a.count, b.count))
    }

    static func isTimestamp(_ value: String) -> Bool {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^(?:Today|Yesterday)(?:[, ]+\d{1,2}:\d{2}(?:\s*[AP]M)?)?$"#,
            #"^\d{1,2}:\d{2}(?:\s*[AP]M)?$"#,
            #"^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)(?:day|sday|nesday|rsday|urday)?[, ]+.*\d.*$"#,
            #"^(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2}(?:,?\s+\d{4})?(?:[, ]+\d{1,2}:\d{2}(?:\s*[AP]M)?)?$"#
        ]
        return patterns.contains { s.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// Propose only adjacent screenshot suffix/prefix overlaps. Nothing is removed here.
    static func overlaps(in archive: ConversationArchive) -> [OverlapProposal] {
        guard archive.sources.count > 1 else { return [] }
        var proposals: [OverlapProposal] = []
        for index in 1..<archive.sources.count {
            let earlier = archive.blocks.filter { $0.sourceID == archive.sources[index - 1].id && !$0.excluded && $0.kind != .interface }
            let later = archive.blocks.filter { $0.sourceID == archive.sources[index].id && !$0.excluded && $0.kind != .interface }
            let limit = min(earlier.count, later.count, 40)
            guard limit >= 2 else { continue }
            for count in stride(from: limit, through: 2, by: -1) {
                let left = Array(earlier.suffix(count)), right = Array(later.prefix(count))
                guard right.map(\.text).joined().count >= 24 else { continue }
                let scores = zip(left, right).map { similarity($0.text, $1.text) }
                if scores.allSatisfy({ $0 >= 0.90 }) {
                    proposals.append(OverlapProposal(earlierIDs: left.map(\.id), laterIDs: right.map(\.id),
                                                      similarity: scores.reduce(0, +) / Double(count)))
                    break
                }
            }
        }
        return proposals.filter { !archive.reviewedOverlaps.contains($0.id) }
    }

    static func fuzzyScore(query: String, text: String) -> Double {
        let q = normalized(String(query.prefix(200))), t = normalized(String(text.prefix(12000)))
        guard !q.isEmpty else { return 0 }
        if t.contains(q) { return 1 }
        let terms = q.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let words = t.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !terms.isEmpty, !words.isEmpty else { return 0 }
        let scores = terms.map { term -> Double in
            if words.contains(term) { return 1 }
            guard term.count >= 5, term.rangeOfCharacter(from: .decimalDigits) == nil else { return 0 }
            return words.filter { abs($0.count - term.count) <= 2 }.map { word -> Double in
                let distance = editDistance(term, word)
                return distance <= 2 ? 1 - Double(distance) / Double(max(term.count, word.count)) : 0
            }.max() ?? 0
        }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
