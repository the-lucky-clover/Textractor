import Foundation
import NaturalLanguage

enum ConversationSearchMode: String, CaseIterable, Identifiable {
    case exact = "Exact", fuzzy = "Fuzzy", semantic = "Related meaning"
    var id: String { rawValue }
}
struct ConversationSearchHit: Identifiable {
    var block: TranscriptBlock
    var score: Double
    var id: UUID { block.id }
}
struct ConversationSearchResult {
    var hits: [ConversationSearchHit]
    var note: String?
}

actor ConversationSearch {
    private var vectors: [String: [Double]] = [:]
    private var embedding: NLEmbedding?
    private var attemptedEmbedding = false

    func search(_ query: String, mode: ConversationSearchMode, blocks: [TranscriptBlock]) -> ConversationSearchResult {
        let query = String(query.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        let blocks = blocks.filter { !$0.excluded }
        guard !query.isEmpty else { return .init(hits: blocks.map { .init(block: $0, score: 1) }, note: nil) }
        var actualMode = mode
        var note: String?
        var queryVector: [Double]?
        if mode == .semantic {
            if !attemptedEmbedding { embedding = NLEmbedding.sentenceEmbedding(for: .english); attemptedEmbedding = true }
            queryVector = embedding?.vector(for: query)
            if queryVector == nil {
                actualMode = .fuzzy
                note = "The on-device English sentence model is unavailable. Showing fuzzy matches."
            } else {
                note = "Related meaning ranks English text by similarity. Results are suggestions, not exact matches or findings of fact."
            }
        }
        var hits: [ConversationSearchHit] = []
        for block in blocks {
            let score: Double
            switch actualMode {
            case .exact: score = ConversationLogic.normalized(block.text).contains(ConversationLogic.normalized(query)) ? 1 : 0
            case .fuzzy: score = ConversationLogic.fuzzyScore(query: query, text: block.text)
            case .semantic:
                let key = block.id.uuidString + ":" + block.text
                if vectors[key] == nil { vectors[key] = embedding?.vector(for: String(block.text.prefix(2000))) }
                score = Self.cosine(queryVector ?? [], vectors[key] ?? [])
            }
            let threshold = actualMode == .semantic ? 0.35 : 0.70
            if score >= threshold { hits.append(.init(block: block, score: score)) }
        }
        if vectors.count > 5000 { vectors.removeAll() }
        return .init(hits: hits.sorted { $0.score > $1.score }, note: note)
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let denominator = sqrt(a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 })
        return denominator > 0 ? dot / denominator : 0
    }
}
