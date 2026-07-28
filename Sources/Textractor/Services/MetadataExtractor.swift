import Foundation
import CoreImage
import Vision
import NaturalLanguage

/// Comprehensive metadata extraction from OCR text and images.
/// Detects URLs, emails, dates, phone numbers, code patterns, error messages,
/// tracking numbers, credit cards, crypto addresses, QR codes, barcodes, and more.
public final class MetadataExtractor {
    public static let shared = MetadataExtractor()

    // MARK: - Compiled Regex Patterns

    private let patterns: [MetadataType: [NSRegularExpression]] = {
        var result: [MetadataType: [NSRegularExpression]] = [:]

        // URLs
        result[.url] = [
            try! NSRegularExpression(pattern: #"https?://[^\s/$.?#].[^\s]*"#, options: [.caseInsensitive]),
            try! NSRegularExpression(pattern: #"www\.[^\s/$.?#].[^\s]*"#, options: [.caseInsensitive]),
            try! NSRegularExpression(pattern: #"\b[a-z0-9.-]+\.[a-z]{2,}(?:/[^\s]*)?"#, options: [.caseInsensitive]),
        ]

        // Emails
        result[.email] = [
            try! NSRegularExpression(pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#),
        ]

        // Phone numbers (various formats)
        result[.phone] = [
            try! NSRegularExpression(pattern: #"\+?1?[-.\s]?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#),
            try! NSRegularExpression(pattern: #"\+\d{1,3}[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,9}\b"#),
        ]

        // Dates (multiple formats)
        result[.date] = [
            try! NSRegularExpression(pattern: #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#),
            try! NSRegularExpression(pattern: #"\b\d{4}[/-]\d{1,2}[/-]\d{1,2}\b"#),
            try! NSRegularExpression(pattern: #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{2,4}\b"#, options: [.caseInsensitive]),
            try! NSRegularExpression(pattern: #"\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4}\b"#, options: [.caseInsensitive]),
            try! NSRegularExpression(pattern: #"\b(?:today|yesterday|tomorrow)\b"#, options: [.caseInsensitive]),
            try! NSRegularExpression(pattern: #"\b\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?\b"#, options: [.caseInsensitive]),
        ]

        // Credit cards (Luhn-validated separately)
        result[.creditCard] = [
            try! NSRegularExpression(pattern: #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#),
        ]

        // Cryptocurrency addresses
        result[.cryptoAddress] = [
            // Bitcoin (legacy, segwit, taproot)
            try! NSRegularExpression(pattern: #"\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b"#),
            try! NSRegularExpression(pattern: #"\bbc1[a-z0-9]{39,59}\b"#, options: [.caseInsensitive]),
            try! NSRegularExpression(pattern: #"\btb1[a-z0-9]{39,59}\b"#, options: [.caseInsensitive]),
            // Ethereum
            try! NSRegularExpression(pattern: #"\b0x[a-fA-F0-9]{40}\b"#),
            // Litecoin
            try! NSRegularExpression(pattern: #"\b[LM3][a-km-zA-HJ-NP-Z1-9]{26,33}\b"#),
        ]

        // Tracking numbers (USPS, UPS, FedEx, DHL)
        result[.trackingNumber] = [
            try! NSRegularExpression(pattern: #"\b9400\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{2}\b"#), // USPS
            try! NSRegularExpression(pattern: #"\b93\d{20,22}\b"#), // USPS
            try! NSRegularExpression(pattern: #"\b1Z[A-Z0-9]{16}\b"#, options: [.caseInsensitive]), // UPS
            try! NSRegularExpression(pattern: #"\b\d{12,15}\b"#), // FedEx (basic)
            try! NSRegularExpression(pattern: #"\b\d{10,14}\b"#), // DHL (basic)
        ]

        // API Keys / Tokens
        result[.apiKey] = [
            // Generic API key patterns
            try! NSRegularExpression(pattern: #"(?i)(?:api[_-]?key|secret[_-]?key|access[_-]?token)[\s:=]+['"]?([a-zA-Z0-9_\-]{20,})['"]?"#),
            try! NSRegularExpression(pattern: #"(?i)(?:bearer|token)[\s:=]+['"]?([a-zA-Z0-9_\-\.]{20,})['"]?"#),
            // AWS
            try! NSRegularExpression(pattern: #"AKIA[0-9A-Z]{16}"#),
            // GitHub
            try! NSRegularExpression(pattern: #"gh[pousr]_[A-Za-z0-9]{36,251}"#),
            // Slack
            try! NSRegularExpression(pattern: #"xox[baprs]-[0-9]{12}-[0-9]{12}-[0-9]{12}-[a-z0-9]{32}"#),
        ]

        // IP Addresses
        result[.ipAddress] = [
            try! NSRegularExpression(pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#),
            try! NSRegularExpression(pattern: #"\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b"#),
        ]

        // MAC Addresses
        result[.macAddress] = [
            try! NSRegularExpression(pattern: #"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#),
        ]

        // UUIDs
        result[.uuid] = [
            try! NSRegularExpression(pattern: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"#),
        ]

        // File paths
        result[.filePath] = [
            try! NSRegularExpression(pattern: #"(?:^|\s)(?:[~/]|\.[/\\])(?:[^/\s\\]+[/\\])+[^/\s\\]+\.[a-zA-Z0-9]{1,5}\b"#),
            try! NSRegularExpression(pattern: #"\b[a-zA-Z]:(?:[\\][^\\/\s:*?""<>|]+)+\\[^\\/\s:*?""<>|]+\.[a-zA-Z0-9]{1,5}\b"#), // Windows
        ]

        // Code patterns
        result[.codeSnippet] = [
            try! NSRegularExpression(pattern: #"(?m)^\s*(?:function|const|let|var|def|class|interface|type|struct|enum|impl|fn|async|await|return|if|else|for|while|switch|case|match|try|catch|finally|throw|import|export|from|as|type|interface)\b"#),
            try! NSRegularExpression(pattern: #"(?m)^\s*[#//].*$"#), // Comments
            try! NSRegularExpression(pattern: #"(?:\{|\[)[^}]*(?:\}|])"#), // Braces/brackets
        ]

        // Error messages
        result[.errorMessage] = [
            try! NSRegularExpression(pattern: #"(?i)(?:error|exception|failed|failure|traceback|stack trace|segfault|panic|abort|crashed):\s*.+"#),
            try! NSRegularExpression(pattern: #"(?i)at\s+[\w\.]+\.[\w]+\([^)]*\)"#), // Stack trace lines
            try! NSRegularExpression(pattern: #"\b(?:Error|Exception|Warning):\s*\d{3,4}"#), // HTTP errors
        ]

        // SSH Keys
        result[.sshKey] = [
            try! NSRegularExpression(pattern: #"-----BEGIN (?:RSA|DSA|EC|OPENSSH) PRIVATE KEY-----"#),
            try! NSRegularExpression(pattern: #"ssh-(?:rsa|dsa|ed25519|ecdsa)\s+[A-Za-z0-9+/]+=*"#),
        ]

        // Docker/Container IDs
        result[.dockerId] = [
            try! NSRegularExpression(pattern: #"\b[0-9a-f]{64}\b"#), // Image digest
            try! NSRegularExpression(pattern: #"\b[0-9a-f]{12}\b"#), // Short container ID
        ]

        // Kubernetes resources
        result[.k8sResource] = [
            try! NSRegularExpression(pattern: #"(?i)(?:pod|service|deployment|configmap|secret|ingress|namespace|pvc|pv)\s+[\w\-]+"#),
            try! NSRegularExpression(pattern: #"kubectl\s+(?:get|describe|apply|delete|logs|exec)\s+"#),
        ]

        // AWS ARNs
        result[.awsArn] = [
            try! NSRegularExpression(pattern: #"arn:aws(?:-[a-z]+)?:[a-z0-9\-]+:[a-z0-9\-]*:[0-9]{12}:.+"#),
        ]

        // JWT Tokens
        result[.jwt] = [
            try! NSRegularExpression(pattern: #"eyJ[a-zA-Z0-9_-]{10,}\.eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}"#),
        ]

        // Prices/Money
        result[.price] = [
            try! NSRegularExpression(pattern: #"[$€£¥]\s*\d+(?:[.,]\d{2})?(?:[KMB])?\b"#),
            try! NSRegularExpression(pattern: #"\b\d+(?:[.,]\d{2})?\s*(?:USD|EUR|GBP|JPY|CNY|BTC|ETH)\b"#, options: [.caseInsensitive]),
        ]

        // Social Security Numbers (US)
        result[.ssn] = [
            try! NSRegularExpression(pattern: #"\b\d{3}-\d{2}-\d{4}\b"#),
        ]

        return result
    }()

    // MARK: - Natural Language Processing

    private let nlTokenizer = NLTokenizer(unit: .word)
    private let nlTagger = NLTagger(tagSchemes: [.lexicalClass, .nameType, .nameTypeOrLexicalClass])

    // MARK: - Public API

    /// Extract all metadata from text.
    public func extract(from text: String) -> ExtractedMetadata {
        var metadata = ExtractedMetadata()

        // Regex-based extraction
        for (type, regexes) in patterns {
            var matches: [String] = []
            for regex in regexes {
                let range = NSRange(text.startIndex..., in: text)
                let found = regex.matches(in: text, options: [], range: range)
                matches.append(contentsOf: found.compactMap {
                    Range($0.range(at: 0), in: text).map { String(text[$0]) }
                })
            }
            if !matches.isEmpty {
                metadata.add(matches, for: type)
            }
        }

        // NLP-based entity extraction
        let nlpEntities = extractNLPEntities(from: text)
        metadata.add(nlpEntities, for: .nlpEntity)

        // Code detection
        if isLikelyCode(text) {
            metadata.add([text], for: .codeSnippet)
        }

        // QR/Barcode detection would need image - handled separately
        return metadata
    }

    /// Extract metadata from an image (QR codes, barcodes, text regions).
    public func extractFromImage(_ image: CGImage, completion: @escaping (ExtractedMetadata) -> Void) {
        var metadata = ExtractedMetadata()

        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])

        // Barcode detection
        let barcodeRequest = VNDetectBarcodesRequest { request, error in
            if let results = request.results as? [VNBarcodeObservation] {
                for result in results {
                    if let payload = result.payloadStringValue {
                        var meta = ExtractedMetadata()
                        meta.add([payload], for: .barcode)
                        metadata.merge(meta)
                    }
                }
            }
        }
        barcodeRequest.symbologies = [.qr, .ean13, .ean8, .upce, .code128, .code39, .code93, .pdf417, .aztec, .dataMatrix]

        // Text detection (for additional OCR-based metadata)
        let textRequest = VNRecognizeTextRequest { request, error in
            if let results = request.results as? [VNRecognizedTextObservation] {
                let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                if !text.isEmpty {
                    let textMeta = self.extract(from: text)
                    metadata.merge(textMeta)
                }
            }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false

        do {
            try requestHandler.perform([barcodeRequest, textRequest])
        } catch {
            LoggerService.shared.error("Vision metadata extraction failed", error: error)
        }

        completion(metadata)
    }

    // MARK: - Internal Helpers

    private func extractNLPEntities(from text: String) -> [NLPEntity] {
        var entities: [NLPEntity] = []

        nlTagger.string = text
        let range = text.startIndex..<text.endIndex

        nlTagger.enumerateTags(in: range, unit: .word, scheme: .nameTypeOrLexicalClass) { tag, tokenRange in
            if let tag = tag {
                let entityText = String(text[tokenRange])
                let type: NLPEntityType
                switch tag {
                case .personalName: type = .person
                case .placeName: type = .location
                case .organizationName: type = .organization
                default: type = .other
                }
                entities.append(NLPEntity(text: entityText, type: type, range: tokenRange))
            }
            return true
        }

        return entities
    }

    private func isLikelyCode(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        let codeIndicators = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("func ") || trimmed.hasPrefix("def ") ||
                   trimmed.hasPrefix("class ") || trimmed.hasPrefix("struct ") ||
                   trimmed.hasPrefix("import ") || trimmed.hasPrefix("const ") ||
                   trimmed.hasPrefix("let ") || trimmed.hasPrefix("var ") ||
                   trimmed.hasPrefix("func ") || trimmed.hasPrefix("fn ") ||
                   trimmed.contains("()") && (trimmed.contains("=") || trimmed.contains("->")) ||
                   trimmed.hasPrefix("//") || trimmed.hasPrefix("#") ||
                   trimmed.hasPrefix("/*") || trimmed.hasPrefix("*/")
        }.count

        return codeIndicators >= 2 || (lines.count > 5 && codeIndicators >= 1)
    }

    // Luhn algorithm for credit card validation
    private func luhnCheck(_ number: String) -> Bool {
        let digits = number.compactMap { $0.wholeNumberValue }
        var sum = 0
        var isSecond = false
        for digit in digits.reversed() {
            var d = digit
            if isSecond {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
            isSecond.toggle()
        }
        return sum % 10 == 0
    }
}

// MARK: - Data Structures

public struct ExtractedMetadata {
    private var storage: [MetadataType: Set<String>] = [:]
    private var nlpEntities: [NLPEntity] = []

    mutating func add(_ values: [String], for type: MetadataType) {
        storage[type, default: []].formUnion(values)
    }

    mutating func add(_ entities: [NLPEntity], for type: MetadataType) {
        nlpEntities.append(contentsOf: entities)
    }

    mutating func merge(_ other: ExtractedMetadata) {
        for (type, values) in other.storage {
            storage[type, default: []].formUnion(values)
        }
        nlpEntities.append(contentsOf: other.nlpEntities)
    }

    func values(for type: MetadataType) -> [String] {
        Array(storage[type] ?? [])
    }

    var nlpEntitiesList: [NLPEntity] { nlpEntities }
    var allTypes: [MetadataType] { Array(storage.keys) }
    var isEmpty: Bool { storage.isEmpty && nlpEntities.isEmpty }
}

public enum MetadataType: String, CaseIterable, Codable, Hashable {
    case url
    case email
    case phone
    case date
    case creditCard
    case cryptoAddress
    case trackingNumber
    case apiKey
    case ipAddress
    case macAddress
    case uuid
    case filePath
    case codeSnippet
    case errorMessage
    case sshKey
    case dockerId
    case k8sResource
    case awsArn
    case jwt
    case price
    case ssn
    case barcode
    case nlpEntity

    public var displayName: String {
        switch self {
        case .url: return "URL"
        case .email: return "Email"
        case .phone: return "Phone"
        case .date: return "Date"
        case .creditCard: return "Credit Card"
        case .cryptoAddress: return "Crypto Address"
        case .trackingNumber: return "Tracking Number"
        case .apiKey: return "API Key"
        case .ipAddress: return "IP Address"
        case .macAddress: return "MAC Address"
        case .uuid: return "UUID"
        case .filePath: return "File Path"
        case .codeSnippet: return "Code Snippet"
        case .errorMessage: return "Error Message"
        case .sshKey: return "SSH Key"
        case .dockerId: return "Docker ID"
        case .k8sResource: return "K8s Resource"
        case .awsArn: return "AWS ARN"
        case .jwt: return "JWT Token"
        case .price: return "Price"
        case .ssn: return "SSN"
        case .barcode: return "Barcode/QR"
        case .nlpEntity: return "Named Entity"
        }
    }

    public var icon: String {
        switch self {
        case .url: return "link"
        case .email: return "envelope"
        case .phone: return "phone"
        case .date: return "calendar"
        case .creditCard: return "creditcard"
        case .cryptoAddress: return "bitcoinsign.circle"
        case .trackingNumber: return "shippingbox"
        case .apiKey: return "key"
        case .ipAddress: return "network"
        case .macAddress: return "macwindow"
        case .uuid: return "number"
        case .filePath: return "doc"
        case .codeSnippet: return "curlybraces"
        case .errorMessage: return "exclamationmark.triangle"
        case .sshKey: return "key.horizontal"
        case .dockerId: return "shippingbox.fill"
        case .k8sResource: return "cube.box"
        case .awsArn: return "cloud"
        case .jwt: return "lock.shield"
        case .price: return "dollarsign.circle"
        case .ssn: return "person.text.rectangle"
        case .barcode: return "barcode.viewfinder"
        case .nlpEntity: return "person"
        }
    }
}

public struct NLPEntity: Codable, Hashable {
    public let text: String
    public let type: NLPEntityType
    public let range: Range<String.Index> // Note: not Codable directly

    public init(text: String, type: NLPEntityType, range: Range<String.Index>) {
        self.text = text
        self.type = type
        self.range = range
    }

    // Custom Codable for range
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        type = try container.decode(NLPEntityType.self, forKey: .type)
        // Range not persisted
        range = text.startIndex..<text.endIndex
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(type, forKey: .type)
    }

    private enum CodingKeys: String, CodingKey { case text, type }
}

public enum NLPEntityType: String, Codable, CaseIterable {
    case person
    case location
    case organization
    case other

    var displayName: String {
        switch self {
        case .person: return "Person"
        case .location: return "Location"
        case .organization: return "Organization"
        case .other: return "Other"
        }
    }
}

// Convenience extension for CaptureRecord
extension CaptureRecord {
    public func extractMetadata() -> ExtractedMetadata {
        MetadataExtractor.shared.extract(from: decryptedOcrText ?? "")
    }
}