import Foundation
import NaturalLanguage

/// Intelligent auto-categorization of captures into smart collections.
/// Uses metadata, OCR text patterns, and ML-based classification.
public final class SmartCollectionClassifier {
    public static let shared = SmartCollectionClassifier()

    // MARK: - Collection Types

    public enum CollectionType: String, CaseIterable, Codable, Hashable {
        case receipt = "receipt"
        case terminal = "terminal"
        case code = "code"
        case book = "book"
        case recipe = "recipe"
        case invoice = "invoice"
        case presentation = "presentation"
        case research = "research"
        case meetingNotes = "meetingNotes"
        case manual = "manual"
        case businessCard = "businessCard"
        case label = "label"
        case package = "package"
        case document = "document"
        case screenshot = "screenshot"
        case whiteboard = "whiteboard"
        case diagram = "diagram"
        case form = "form"
        case idCard = "idCard"
        case prescription = "prescription"
        case article = "article"
        case email = "email"
        case chat = "chat"
        case other = "other"

        public var displayName: String {
            switch self {
            case .receipt: return "Receipts"
            case .terminal: return "Terminal"
            case .code: return "Code"
            case .book: return "Books"
            case .recipe: return "Recipes"
            case .invoice: return "Invoices"
            case .presentation: return "Presentations"
            case .research: return "Research"
            case .meetingNotes: return "Meeting Notes"
            case .manual: return "Manuals"
            case .businessCard: return "Business Cards"
            case .label: return "Labels"
            case .package: return "Packages"
            case .document: return "Documents"
            case .screenshot: return "Screenshots"
            case .whiteboard: return "Whiteboards"
            case .diagram: return "Diagrams"
            case .form: return "Forms"
            case .idCard: return "ID Cards"
            case .prescription: return "Prescriptions"
            case .article: return "Articles"
            case .email: return "Emails"
            case .chat: return "Chats"
            case .other: return "Other"
            }
        }

        public var icon: String {
            switch self {
            case .receipt: return "receipt"
            case .terminal: return "terminal"
            case .code: return "curlybraces"
            case .book: return "book"
            case .recipe: return "fork.knife"
            case .invoice: return "doc.text.fill"
            case .presentation: return "rectangle.on.rectangle"
            case .research: return "magnifyingglass"
            case .meetingNotes: return "person.2.fill"
            case .manual: return "book.closed"
            case .businessCard: return "person.crop.rectangle"
            case .label: return "tag"
            case .package: return "shippingbox"
            case .document: return "doc"
            case .screenshot: return "camera.viewfinder"
            case .whiteboard: return "scribble"
            case .diagram: return "chart.xyaxis.line"
            case .form: return "doc.plaintext"
            case .idCard: return "person.text.rectangle"
            case .prescription: return "cross.case"
            case .article: return "newspaper"
            case .email: return "envelope"
            case .chat: return "message"
            case .other: return "folder"
            }
        }

        public var color: String {
            switch self {
            case .receipt: return "#FF6B35"
            case .terminal: return "#00D4AA"
            case .code: return "#6C5CE7"
            case .book: return "#A29BFE"
            case .recipe: return "#FD79A8"
            case .invoice: return "#00B894"
            case .presentation: return "#636E72"
            case .research: return "#74B9FF"
            case .meetingNotes: return "#FAB1A0"
            case .manual: return "#B2BEC3"
            case .businessCard: return "#E17055"
            case .label: return "#FDCB6E"
            case .package: return "#E84393"
            case .document: return "#636E72"
            case .screenshot: return "#74B9FF"
            case .whiteboard: return "#A29BFE"
            case .diagram: return "#00CEC9"
            case .form: return "#B2BEC3"
            case .idCard: return "#D63031"
            case .prescription: return "#00B894"
            case .article: return "#0984E3"
            case .email: return "#00CEC9"
            case .chat: return "#FD79A8"
            case .other: return "#636E72"
            }
        }
    }

    // MARK: - Classification Patterns

    private let patterns: [CollectionType: [NSRegularExpression]] = {
        var result: [CollectionType: [NSRegularExpression]] = [:]

        func rx(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }

        result[.receipt] = [
            rx(#"(?i)\b(receipt|total|subtotal|tax|vat|change|cash|credit|debit|card|visa|mastercard|amex|discover)\b"#),
            rx(#"(?i)\b(store|shop|merchant|register|transaction|purchase|item|qty|price)\b"#),
            rx(#"\$\s*\d+\.\d{2}"#),
            rx(#"(?i)\bthank you for your purchase\b"#),
        ]

        result[.terminal] = [
            rx(#"(?m)^\s*\$\s"#),  // $ prompt
            rx(#"(?m)^\s*[#%]\s"#),  // # or % prompt
            rx(#"(?m)^\w+@\w+:\s*~\s*\$"#),  // user@host:~$
            rx(#"(?i)\b(git|npm|yarn|pip|cargo|brew|docker|kubectl|ssh|scp|rsync|tar|grep|sed|awk|vim|nano|code|ls|cd|mkdir|rm|cp|mv)\b"#),
            rx(#"(?i)\b(error|warning|fatal|exception|traceback|stack trace|segmentation fault)\b"#),
            rx(#"(?m)^\s*\[\d+:\d+:\d+\]"#),  // timestamps
        ]

        result[.code] = [
            rx(#"(?m)^\s*(func|def|class|class|struct|interface|type|enum|impl|fn|async|await|return|if|else|for|while|switch|case|match|try|catch|finally|throw|import|export|from|as|type|protocol)\b"#),
            rx(#"(?m)^\s*(const|let|var|public|private|protected|static|final|abstract|override)\s+\w+"#),
            rx(#"(?m)^\s*(import|include|using|require|use)\s+"#),
            rx(#"(?m)^\s*//.*"#),  // comments
            rx(#"(?m)^\s*/\*.*\*/"#),  // block comments
            rx(#"\b(?:function|const|let|var|public|private|static|async|await|return|if|else|for|while|switch|case|match|try|catch|finally|throw|import|export|from|as|type|interface|struct|enum|impl|fn|async|await)\b"#),
        ]

        result[.book] = [
            rx(#"(?i)\b(chapter|page|isbn|author|publisher|edition|copyright)\b"#),
            rx(#"(?i)\b\d{1,3}[- ]?\d{1,5}[- ]?\d{1,5}[- ]?\d{1,5}[- ]?\d\b"#), // ISBN
        ]

        result[.recipe] = [
            rx(#"(?i)\b(ingredients|instructions|directions|servings|prep|cook|bake|minutes|hours|oven|cup|tbsp|tsp|oz|lb|gram)\b"#),
        ]

        result[.invoice] = [
            rx(#"(?i)\b(invoice|bill|due date|net 30|net 60|payment terms|remit|purchase order|po #)\b"#),
            rx(#"(?i)\b(total due|amount due|balance due)\b"#),
        ]

        result[.presentation] = [
            rx(#"(?i)\b(slide|presentation|agenda|overview|summary|conclusion|q&a|questions)\b"#),
            rx(#"(?i)\b(speaker|presenter|audience|attendees)\b"#),
        ]

        result[.research] = [
            rx(#"(?i)\b(abstract|methodology|results|conclusion|references|citation|doi|arxiv|pubmed)\b"#),
            rx(#"(?i)\b(hypothesis|experiment|analysis|statistical|significant|p-value)\b"#),
        ]

        result[.meetingNotes] = [
            rx(#"(?i)\b(meeting|agenda|action items|action item|follow up|follow-up|attendees|minutes)\b"#),
            rx(#"(?i)\b(todo|action|decided|decision|pending|blocked|owner)\b"#),
        ]

        result[.manual] = [
            rx(#"(?i)\b(manual|guide|tutorial|how to|step|instruction|setup|install|configure|configure)\b"#),
        ]

        result[.businessCard] = [
            rx(#"(?i)\b(phone|email|address|title|company|linkedin|twitter|github)\b"#),
            rx(#"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#),
            rx(#"\+\d{1,3}[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,9}\b"#),
        ]

        result[.email] = [
            rx(#"(?i)\b(from|to|subject|cc|bcc|dear|sincerely|regards|best regards)\b"#),
            rx(#"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#),
        ]

        result[.chat] = [
            rx(#"(?i)\b(slack|discord|teams|zoom|message|replied|thread|channel)\b"#),
            rx(#"(?i)\b(today|yesterday|just now|minute|hour)\s*ago\b"#),
        ]

        result[.article] = [
            rx(#"(?i)\b(article|author|published|by|read more|source)\b"#),
            rx(#"(?i)\b(headline|headline|byline|dateline)\b"#),
        ]

        result[.package] = [
            rx(#"(?i)\b(tracking|tracking number|shipment|delivered|out for delivery|shipped)\b"#),
            rx(#"\b1Z[A-Z0-9]{16}\b"#), // UPS
            rx(#"\b\d{12,15}\b"#), // FedEx basic
        ]

        result[.whiteboard] = [
            rx(#"(?i)\b(whiteboard|diagram|sketch|draw|arrow|box|circle|line)\b"#),
        ]

        result[.diagram] = [
            rx(#"(?i)\b(diagram|flowchart|architecture|component|sequence|class|entity|relationship)\b"#),
        ]

        result[.form] = [
            rx(#"(?i)\b(form|field|required|optional|submit|checkbox|radio|dropdown|select)\b"#),
        ]

        result[.idCard] = [
            rx(#"(?i)\b(id|badge|employee|access|security|clearance|expires|issued)\b"#),
        ]

        result[.prescription] = [
            rx(#"(?i)\b(rx|prescription|dosage|mg|ml|tablet|capsule|refill|pharmacy|doctor)\b"#),
        ]

        result[.label] = [
            rx(#"(?i)\b(label|ingredients|nutrition|serving|expires|best by|lot|batch)\b"#),
        ]

        result[.package] = [
            rx(#"(?i)\b(package|parcel|tracking|shipped|delivered|carrier)\b"#),
        ]

        result[.screenshot] = [
            rx(#"(?i)\b(screenshot|capture|captured|screen)\b"#),
        ]

        result[.prescription] = [
            rx(#"(?i)\b(rx|prescription|dosage|mg|ml|tablet|capsule|refill|pharmacy|doctor)\b"#),
        ]

        return result
    }()

    // MARK: - Natural Language Processing

    private let nlTokenizer = NLTokenizer(unit: .word)
    private let nlTagger = NLTagger(tagSchemes: [.lexicalClass, .nameType, .nameTypeOrLexicalClass])

    // MARK: - Public API

    /// Classify a capture into a collection type based on text and metadata.
    public func classify(text: String, metadata: ExtractedMetadata, imageWidth: Int, imageHeight: Int) -> CollectionType {
        var scores: [CollectionType: Double] = [:]

        // Score based on regex patterns
        for (type, regexes) in patterns {
            var score = 0.0
            for regex in regexes {
                let matches = regex.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                if matches > 0 {
                    score += Double(matches) * 1.5
                }
            }
            scores[type] = score
        }

        // Boost based on metadata
        if !metadata.values(for: .url).isEmpty { scores[.article, default: 0] += 1.0; scores[.email, default: 0] += 0.5 }
        if !metadata.values(for: .email).isEmpty { scores[.email, default: 0] += 2.0; scores[.businessCard, default: 0] += 1.0 }
        if !metadata.values(for: .phone).isEmpty { scores[.businessCard, default: 0] += 1.5; scores[.invoice, default: 0] += 0.5 }
        if !metadata.values(for: .trackingNumber).isEmpty { scores[.package, default: 0] += 3.0 }
        if !metadata.values(for: .cryptoAddress).isEmpty { scores[.article, default: 0] += 1.0 }
        if !metadata.values(for: .creditCard).isEmpty { scores[.receipt, default: 0] += 2.0; scores[.invoice, default: 0] += 1.0 }
        if !metadata.values(for: .apiKey).isEmpty { scores[.code, default: 0] += 2.0; scores[.terminal, default: 0] += 1.0 }
        if !metadata.values(for: .filePath).isEmpty { scores[.terminal, default: 0] += 1.0; scores[.code, default: 0] += 1.0 }
        if !metadata.values(for: .sshKey).isEmpty { scores[.terminal, default: 0] += 2.0 }
        if !metadata.values(for: .dockerId).isEmpty { scores[.terminal, default: 0] += 2.0 }
        if let urls = metadata.values(for: .url) as? [String], urls.count > 3 { scores[.research, default: 0] += 1.0 }

        // Aspect ratio hints
        let aspectRatio = Double(imageWidth) / Double(max(imageHeight, 1))
        if aspectRatio > 2.0 { scores[.terminal, default: 0] += 1.0; scores[.code, default: 0] += 0.5 }
        if aspectRatio < 0.5 { scores[.receipt, default: 0] += 1.0; scores[.label, default: 0] += 1.0 }

        // NLP-based classification
        let nlpScores = classifyWithNLP(text: text)
        for (type, score) in nlpScores {
            scores[type, default: 0] += score
        }

        // Return highest scoring type, default to .other
        return scores.max { $0.value < $1.value }?.key ?? .other
    }

    // MARK: - NLP-based Classification

    private func classifyWithNLP(text: String) -> [CollectionType: Double] {
        var scores: [CollectionType: Double] = [:]

        nlTagger.string = text
        let range = text.startIndex..<text.endIndex

        // Count named entities
        var personCount = 0
        var orgCount = 0
        var locationCount = 0

        nlTagger.enumerateTags(in: range, unit: .word, scheme: .nameTypeOrLexicalClass) { tag, tokenRange in
            if let tag = tag {
                switch tag {
                case .personalName: personCount += 1
                case .organizationName: orgCount += 1
                case .placeName: locationCount += 1
                default: break
                }
            }
            return true
        }

        if personCount > 2 { scores[.businessCard, default: 0] += 1.0 }
        if orgCount > 1 { scores[.invoice, default: 0] += 0.5; scores[.businessCard, default: 0] += 0.5 }
        if locationCount > 1 { scores[.invoice, default: 0] += 0.5; scores[.receipt, default: 0] += 0.5 }

        // Lexical class analysis
        var codeTokenCount = 0
        var totalTokens = 0
        nlTagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            totalTokens += 1
            if tag == .otherWord || tag == .number {
                let token = String(text[tokenRange])
                if token.contains("{") || token.contains("}") || token.contains("(") || token.contains(")") ||
                   token.contains(";") || token.contains(":=") || token.contains("->") || token.contains("=>") ||
                   token.contains("==") || token.contains("!=") || token.contains(">=") || token.contains("<=") {
                    codeTokenCount += 1
                }
            }
            return true
        }

        if totalTokens > 10 && Double(codeTokenCount) / Double(totalTokens) > 0.15 {
            scores[.code, default: 0] += 2.0
        }

        return scores
    }

    // MARK: - Convenience

    /// Classify a capture record directly
    public func classify(record: CaptureRecord) -> CollectionType {
        let text = record.decryptedOcrText ?? ""
        let metadata = MetadataExtractor.shared.extract(from: text)
        return classify(text: text, metadata: metadata, imageWidth: record.imageWidth, imageHeight: record.imageHeight)
    }

    /// Get all collection types with non-zero captures
    public func collectionsWithCounts(records: [CaptureRecord]) -> [(CollectionType, Int)] {
        var counts: [CollectionType: Int] = [:]
        for record in records {
            let type = classify(record: record)
            counts[type, default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}