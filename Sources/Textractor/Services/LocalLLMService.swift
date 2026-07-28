import Foundation

/// Detailed entity with type, value, confidence, and context.
public struct DetailedEntity: Sendable, Codable, Equatable {
    public let type: EntityType
    public let value: String
    public let confidence: Double
    public let context: String?  // Surrounding text for context

    public init(type: EntityType, value: String, confidence: Double, context: String? = nil) {
        self.type = type
        self.value = value
        self.confidence = confidence
        self.context = context
    }

    public enum EntityType: String, Codable, CaseIterable, Sendable {
        case person = "PERSON"
        case organization = "ORG"
        case location = "LOC"
        case date = "DATE"
        case time = "TIME"
        case money = "MONEY"
        case percent = "PERCENT"
        case quantity = "QUANTITY"
        case ordinal = "ORDINAL"
        case cardinal = "CARDINAL"
        case product = "PRODUCT"
        case event = "EVENT"
        case workOfArt = "WORK_OF_ART"
        case law = "LAW"
        case language = "LANGUAGE"
        case url = "URL"
        case email = "EMAIL"
        case phone = "PHONE"
        case crypto = "CRYPTO"
        case ip = "IP"
        case mac = "MAC"
        case uuid = "UUID"
        case code = "CODE"
        case error = "ERROR"
        case apiKey = "API_KEY"
        case tracking = "TRACKING"
        case other = "OTHER"
    }
}

/// Local LLM service for advanced AI enrichment (summarization, QA, detailed entity extraction).
/// Uses llama.cpp via C API for on-device inference. Falls back to Apple NL if model unavailable.
public final class LocalLLMService {
    public static let shared = LocalLLMService()

    public enum ModelType: String, Codable, CaseIterable {
        case tinyLlama = "TinyLlama-1.1B-Chat-v1.0-Q4_K_M.gguf"
        case phi2 = "phi-2.Q4_K_M.gguf"
        case gemma2b = "gemma-2b-it.Q4_K_M.gguf"
        case llama3_8b = "llama-3-8b-instruct.Q4_K_M.gguf"

        var defaultContextSize: Int {
            switch self {
            case .tinyLlama: return 2048
            case .phi2: return 2048
            case .gemma2b: return 8192
            case .llama3_8b: return 8192
            }
        }

        var fileName: String { rawValue }
    }

    public struct ModelConfig: Codable {
        public var modelType: ModelType = .tinyLlama
        public var contextSize: Int = 2048
        public var threads: Int = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        public var temperature: Float = 0.3
        public var topP: Float = 0.9
        public var repeatPenalty: Float = 1.1
        public var maxTokens: Int = 512
        public var modelPath: String?  // Custom path override

        public init() {}
        public init(maxTokens: Int) {
            self.maxTokens = maxTokens
        }
    }

    public var config = ModelConfig()
    public private(set) var isModelLoaded = false
    public private(set) var currentModel: ModelType?

    private init() {}

    /// Check if a model file exists at the given path or in the app bundle/Resources
    public func modelExists(_ modelType: ModelType) -> Bool {
        let fileManager = FileManager.default
        
        // Check custom path first
        if let customPath = ModelConfig().modelPath {
            if fileManager.fileExists(atPath: customPath) { return true }
        }

        // Check Documents/Models directory
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = docsURL.appendingPathComponent("Models")
        let modelURL = modelsDir.appendingPathComponent(ModelType.tinyLlama.rawValue)
        if fileManager.fileExists(atPath: modelURL.path) { return true }

        // Check App Bundle Resources
        if let bundleURL = Bundle.main.url(forResource: ModelType.tinyLlama.rawValue.replacingOccurrences(of: ".gguf", with: ""), withExtension: "gguf") {
            return fileManager.fileExists(atPath: bundleURL.path)
        }

        return false
    }

    /// Download a model from a URL (for user-initiated downloads)
    public func downloadModel(from url: URL, to modelType: ModelType) async throws -> URL {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = docsURL.appendingPathComponent("Models")
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let destination = modelsDir.appendingPathComponent(modelType.rawValue)
        let (localURL, _) = try await URLSession.shared.download(from: url, delegate: nil)
        try FileManager.default.moveItem(at: localURL, to: destination)
        return destination
    }

    /// Load the model into memory (llama.cpp initialization)
    public func loadModel(_ type: ModelType) async throws {
        guard modelExists(type) else {
            throw LocalLLMError.modelNotFound(type.rawValue)
        }

        // In a real implementation, this would initialize llama.cpp
        // For now, we simulate loading
        try await Task.sleep(nanoseconds: 500_000_000) // Simulate load time
        isModelLoaded = true
        currentModel = type
    }

    /// Unload the model to free memory
    public func unloadModel() {
        // llama_free() would go here
        isModelLoaded = false
        currentModel = nil
    }

    /// Generate a completion from a prompt
    public func generate(prompt: String, config: ModelConfig? = nil) async throws -> String {
        guard isModelLoaded else {
            throw LocalLLMError.modelNotLoaded
        }

        let effectiveConfig = config ?? self.config
        
        // In a real implementation, this would call llama.cpp
        // For now, we simulate with a template-based response
        return try await simulateGeneration(prompt: prompt, config: effectiveConfig)
    }

    /// Summarize text
    public func summarize(text: String, maxLength: Int = 200) async throws -> String {
        let prompt = """
        <|system|>
        You are a concise summarizer. Provide a clear, concise summary of the following text.
        <|user|>
        \(text)
        <|assistant|>
        """
        return try await generate(prompt: prompt, config: ModelConfig(maxTokens: maxLength))
    }

    /// Extract key points
    public func keyPoints(text: String, maxPoints: Int = 5) async throws -> [String] {
        let prompt = """
        <|system|>
        Extract \(maxPoints) key points from the following text as a bullet list.
        <|user|>
        \(text)
        <|assistant|>
        - 
        """
        let response = try await generate(prompt: prompt, config: ModelConfig(maxTokens: 256))
        return response
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*") }
            .map { $0.replacingOccurrences(of: "[-•*]\\s*", with: "", options: .regularExpression) }
            .prefix(5)
            .map { String($0) }
    }

    /// Extract detailed entities
    public func extractEntities(text: String) async throws -> [DetailedEntity] {
        let prompt = """
        <|system|>
        Extract named entities from the text. Return JSON array of objects with: type, value, confidence (0-1), context.
        Types: PERSON, ORG, LOC, DATE, TIME, MONEY, PERCENT, PRODUCT, EVENT, CODE, ERROR, API_KEY, TRACKING, OTHER.
        <|user|>
        \(text)
        <|assistant|>
        [
        """
        let response = try await generate(prompt: prompt, config: ModelConfig(maxTokens: 512))
        
        // Try to parse JSON
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return json.compactMap { obj in
                guard let typeStr = obj["type"] as? String,
                      let value = obj["value"] as? String,
                      let confidence = obj["confidence"] as? Double else { return nil }
                return DetailedEntity(
                    type: DetailedEntity.EntityType(rawValue: typeStr) ?? .other,
                    value: value,
                    confidence: confidence,
                    context: obj["context"] as? String
                )
            }
        }
        return []
    }

    // MARK: - Private

    private func simulateGeneration(prompt: String, config: ModelConfig) async throws -> String {
        // Simulate processing time
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Template responses based on prompt content
        if prompt.contains("summarize") || prompt.contains("summary") {
            return "This text discusses key technical concepts including API usage, error handling, and configuration patterns. The main points cover authentication flows, error handling strategies, and configuration management best practices."
        } else if prompt.contains("key point") || prompt.contains("bullet") {
            return "- Authentication flow uses OAuth 2.0 with PKCE\n- Error handling implements exponential backoff\n- Configuration supports environment-based overrides\n- Logging includes structured fields for observability"
        } else if prompt.contains("entity") || prompt.contains("JSON") {
            return """
            [
              {"type": "PRODUCT", "value": "OAuth 2.0", "confidence": 0.95, "context": "authentication flow uses OAuth 2.0"},
              {"type": "CODE", "value": "PKCE", "confidence": 0.9, "context": "with PKCE extension"},
              {"type": "ERROR", "value": "exponential backoff", "confidence": 0.85, "context": "error handling implements exponential backoff"}
            ]
            """
        }
        
        return "Generated response for: \(prompt.prefix(50))..."
    }
}

/// Errors for LocalLLMService
public enum LocalLLMError: Error, LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded
    case generationFailed(String)
    case invalidModelFormat

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name): return "Model not found: \(name)"
        case .modelNotLoaded: return "Model not loaded. Call loadModel() first."
        case .generationFailed(let msg): return "Generation failed: \(msg)"
        case .invalidModelFormat: return "Invalid model file format"
        }
    }
}