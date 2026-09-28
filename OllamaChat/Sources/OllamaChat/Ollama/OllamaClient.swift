import Foundation

enum OllamaError: LocalizedError {
    case invalidAddress(String)
    case http(status: Int, message: String?)
    case server(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let address):
            return "L’adresse du serveur « \(address) » n’est pas valide."
        case .http(let status, let message):
            if let message, !message.isEmpty { return message }
            return "Ollama a répondu avec le code HTTP \(status)."
        case .server(let message):
            return message
        case .emptyResponse:
            return "Ollama a renvoyé une réponse vide."
        }
    }
}

struct OllamaModel: Identifiable, Decodable, Hashable {
    struct Details: Decodable, Hashable {
        let family: String?
        let parameterSize: String?
        let quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case family
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }

    let name: String
    let size: Int64?
    let digest: String?
    let details: Details?

    var id: String { name }

    var summary: String {
        var parts: [String] = []
        if let parameters = details?.parameterSize, !parameters.isEmpty { parts.append(parameters) }
        if let quantization = details?.quantizationLevel, !quantization.isEmpty { parts.append(quantization) }
        if let size { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }
}

/// Ce qu’un modèle sait faire, d’après `/api/show` (ou, pour les anciennes versions d’Ollama,
/// d’après son nom).
struct ModelInfo: Equatable {
    var capabilities: Set<String>
    /// Taille de contexte maximale prévue par le modèle.
    var maxContextLength: Int?
    var family: String?
    var name: String

    var supportsThinking: Bool { capabilities.contains("thinking") }
    var supportsTools: Bool { capabilities.contains("tools") }
    var supportsVision: Bool { capabilities.contains("vision") }
    var isEmbeddingModel: Bool { capabilities.contains("embedding") && !capabilities.contains("completion") }
    /// gpt-oss ne désactive pas sa réflexion mais accepte trois niveaux.
    var usesThinkingLevels: Bool {
        name.lowercased().hasPrefix("gpt-oss") || (family?.lowercased().contains("gptoss") ?? false)
    }

    /// Capacités devinées à partir du nom, quand Ollama ne les indique pas.
    static func guessed(for name: String) -> ModelInfo {
        let lower = name.lowercased()
        var capabilities: Set<String> = ["completion"]
        let thinkers = ["qwen3", "deepseek-r1", "gpt-oss", "magistral", "phi4-reasoning", "cogito", "qwq"]
        if thinkers.contains(where: lower.hasPrefix) { capabilities.insert("thinking") }
        let vision = ["llava", "gemma3", "qwen2.5vl", "qwen2.5-vl", "moondream", "minicpm-v", "llama3.2-vision", "granite3.2-vision", "bakllava", "mistral-small3"]
        if vision.contains(where: lower.hasPrefix) || lower.contains("vision") { capabilities.insert("vision") }
        let embedding = ["nomic-embed", "mxbai-embed", "all-minilm", "bge-", "snowflake-arctic-embed", "embeddinggemma", "granite-embedding", "paraphrase-multilingual"]
        if embedding.contains(where: lower.hasPrefix) || lower.contains("embed") {
            capabilities = ["embedding"]
        }
        return ModelInfo(capabilities: capabilities, maxContextLength: nil, family: nil, name: name)
    }
}

struct ToolCall: Codable, Equatable {
    struct Function: Codable, Equatable {
        var name: String
        var arguments: [String: JSONValue]
    }

    var function: Function
}

struct ChatChunk: Decodable {
    struct Message: Decodable {
        let content: String?
        let thinking: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case content, thinking
            case toolCalls = "tool_calls"
        }
    }

    let message: Message?
    let done: Bool?
    let evalCount: Int?
    /// Durée de génération, en nanosecondes.
    let evalDuration: Int64?
    let promptEvalCount: Int?

    enum CodingKeys: String, CodingKey {
        case message, done
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
        case promptEvalCount = "prompt_eval_count"
    }
}

struct PullProgress: Decodable {
    let status: String?
    let total: Int64?
    let completed: Int64?
}

/// Client de l’API REST d’Ollama (celle qu’utilise aussi la commande `ollama`).
/// Documentation : https://github.com/ollama/ollama/blob/main/docs/api.md
struct OllamaClient {
    struct Message: Encodable, Equatable {
        var role: String
        var content: String
        /// Images encodées en base64 (modèles de vision).
        var images: [String]?
        var toolCalls: [ToolCall]?
        /// Nom de l’outil dont ce message rapporte le résultat (rôle `tool`).
        var toolName: String?

        init(role: String, content: String, images: [String]? = nil, toolCalls: [ToolCall]? = nil, toolName: String? = nil) {
            self.role = role
            self.content = content
            self.images = images
            self.toolCalls = toolCalls
            self.toolName = toolName
        }

        enum CodingKeys: String, CodingKey {
            case role, content, images
            case toolCalls = "tool_calls"
            case toolName = "tool_name"
        }
    }

    struct Options: Encodable, Equatable {
        var temperature: Double?
        var numCtx: Int?
        var numPredict: Int?

        var isEmpty: Bool { temperature == nil && numCtx == nil && numPredict == nil }

        enum CodingKeys: String, CodingKey {
            case temperature
            case numCtx = "num_ctx"
            case numPredict = "num_predict"
        }
    }

    /// Valeur du paramètre `think` : oui/non, ou niveau pour gpt-oss.
    enum Think: Encodable, Equatable {
        case enabled(Bool)
        case level(String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .enabled(let value): try container.encode(value)
            case .level(let value): try container.encode(value)
            }
        }
    }

    /// Outil proposé au modèle (appel de fonction).
    struct Tool: Encodable, Equatable {
        struct Function: Encodable, Equatable {
            var name: String
            var description: String
            var parameters: JSONValue
        }

        var type = "function"
        var function: Function

        init(name: String, description: String, parameters: JSONValue) {
            function = Function(name: name, description: description, parameters: parameters)
        }
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options?
        let think: Think?
        let tools: [Tool]?
        let format: JSONValue?
        let keepAlive: String?

        enum CodingKeys: String, CodingKey {
            case model, messages, stream, options, think, tools, format
            case keepAlive = "keep_alive"
        }
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable {
            let content: String?
            let thinking: String?
        }

        let message: Message?
    }

    private struct ModelRequest: Encodable {
        let model: String
        let stream: Bool?
    }

    private struct ShowResponse: Decodable {
        struct Details: Decodable {
            let family: String?
        }

        let capabilities: [String]?
        let modelInfo: [String: JSONValue]?
        let details: Details?

        enum CodingKeys: String, CodingKey {
            case capabilities, details
            case modelInfo = "model_info"
        }
    }

    private struct EmbedRequest: Encodable {
        let model: String
        let input: [String]
    }

    private struct EmbedResponse: Decodable {
        let embeddings: [[Double]]
    }

    private struct TagsResponse: Decodable {
        let models: [OllamaModel]
    }

    private struct ErrorResponse: Decodable {
        let error: String?
    }

    let baseURL: URL

    init(address: String) throws {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = AppDefaults.serverURL }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host() != nil else {
            throw OllamaError.invalidAddress(address)
        }
        baseURL = url
    }

    func listModels() async throws -> [OllamaModel] {
        let data = try await perform(request("api/tags", timeout: 5))
        return try JSONDecoder().decode(TagsResponse.self, from: data).models
    }

    /// Capacités et taille de contexte d’un modèle.
    func modelInfo(_ name: String) async throws -> ModelInfo {
        let body = try JSONEncoder().encode(ModelRequest(model: name, stream: nil))
        let data = try await perform(request("api/show", method: "POST", body: body, timeout: 10))
        let response = try JSONDecoder().decode(ShowResponse.self, from: data)
        guard let capabilities = response.capabilities, !capabilities.isEmpty else {
            var guess = ModelInfo.guessed(for: name)
            guess.maxContextLength = Self.contextLength(in: response.modelInfo)
            return guess
        }
        return ModelInfo(
            capabilities: Set(capabilities),
            maxContextLength: Self.contextLength(in: response.modelInfo),
            family: response.details?.family,
            name: name
        )
    }

    func deleteModel(_ name: String) async throws {
        let body = try JSONEncoder().encode(ModelRequest(model: name, stream: nil))
        _ = try await perform(request("api/delete", method: "DELETE", body: body))
    }

    func chat(
        model: String,
        messages: [Message],
        options: Options?,
        think: Think? = nil,
        tools: [Tool]? = nil
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        stream("api/chat", body: ChatRequest(
            model: model, messages: messages, stream: true, options: options,
            think: think, tools: tools, format: nil, keepAlive: nil
        ))
    }

    /// Réponse complète, sans diffusion progressive : titres, extraction de souvenirs.
    /// `format` peut contenir un schéma JSON que la réponse devra respecter.
    func complete(
        model: String,
        messages: [Message],
        options: Options?,
        think: Think? = nil,
        format: JSONValue? = nil
    ) async throws -> String {
        let body = try JSONEncoder().encode(ChatRequest(
            model: model, messages: messages, stream: false, options: options,
            think: think, tools: nil, format: format, keepAlive: nil
        ))
        let data = try await perform(request("api/chat", method: "POST", body: body, timeout: 300))
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.message?.content else { throw OllamaError.emptyResponse }
        return content
    }

    /// Vecteurs (embeddings) des textes, pour retrouver les passages pertinents d’un document.
    func embed(model: String, inputs: [String]) async throws -> [[Float]] {
        let body = try JSONEncoder().encode(EmbedRequest(model: model, input: inputs))
        let data = try await perform(request("api/embed", method: "POST", body: body, timeout: 300))
        return try JSONDecoder().decode(EmbedResponse.self, from: data).embeddings.map { $0.map(Float.init) }
    }

    func pull(model: String) -> AsyncThrowingStream<PullProgress, Error> {
        stream("api/pull", body: ModelRequest(model: model, stream: true))
    }

    private static func contextLength(in modelInfo: [String: JSONValue]?) -> Int? {
        guard let modelInfo else { return nil }
        return modelInfo.first { $0.key.hasSuffix(".context_length") }?.value.intValue
    }

    // MARK: - Transport

    /// Envoie une requête POST et décode la réponse en flux (un objet JSON par ligne).
    /// Annuler la tâche qui consomme le flux annule la requête HTTP.
    private func stream<Chunk: Decodable>(_ path: String, body: some Encodable) -> AsyncThrowingStream<Chunk, Error> {
        let urlRequest: URLRequest
        do {
            // Délai long : le premier octet n’arrive qu’une fois le modèle chargé en mémoire.
            urlRequest = request(path, method: "POST", body: try JSONEncoder().encode(body), timeout: 600)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw OllamaError.http(status: http.statusCode, message: Self.errorMessage(in: data))
                    }
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines where !line.isEmpty {
                        let data = Data(line.utf8)
                        if let message = (try? decoder.decode(ErrorResponse.self, from: data))?.error {
                            throw OllamaError.server(message)
                        }
                        continuation.yield(try decoder.decode(Chunk.self, from: data))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OllamaError.http(status: http.statusCode, message: Self.errorMessage(in: data))
        }
        return data
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 30) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func errorMessage(in data: Data) -> String? {
        if let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error {
            return message
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(300))
    }
}
