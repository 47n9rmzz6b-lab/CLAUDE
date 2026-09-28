import Foundation

enum OllamaError: LocalizedError {
    case invalidAddress(String)
    case http(status: Int, message: String?)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let address):
            return "L’adresse du serveur « \(address) » n’est pas valide."
        case .http(let status, let message):
            if let message, !message.isEmpty { return message }
            return "Ollama a répondu avec le code HTTP \(status)."
        case .server(let message):
            return message
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

struct ChatChunk: Decodable {
    struct Message: Decodable {
        let content: String?
        let thinking: String?
    }

    let message: Message?
    let done: Bool?
    let evalCount: Int?
    /// Durée de génération, en nanosecondes.
    let evalDuration: Int64?

    enum CodingKeys: String, CodingKey {
        case message, done
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

struct PullProgress: Decodable {
    let status: String?
    let total: Int64?
    let completed: Int64?
}

/// Client minimal de l’API REST d’Ollama (celle qu’utilise aussi la commande `ollama`).
/// Documentation : https://github.com/ollama/ollama/blob/main/docs/api.md
struct OllamaClient {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Options: Encodable {
        var temperature: Double?
        var numCtx: Int?

        var isEmpty: Bool { temperature == nil && numCtx == nil }

        enum CodingKeys: String, CodingKey {
            case temperature
            case numCtx = "num_ctx"
        }
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options?
    }

    private struct ModelRequest: Encodable {
        let model: String
        let stream: Bool?
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

    func deleteModel(_ name: String) async throws {
        let body = try JSONEncoder().encode(ModelRequest(model: name, stream: nil))
        _ = try await perform(request("api/delete", method: "DELETE", body: body))
    }

    func chat(model: String, messages: [Message], options: Options?) -> AsyncThrowingStream<ChatChunk, Error> {
        stream("api/chat", body: ChatRequest(model: model, messages: messages, stream: true, options: options))
    }

    func pull(model: String) -> AsyncThrowingStream<PullProgress, Error> {
        stream("api/pull", body: ModelRequest(model: model, stream: true))
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

    private static func errorMessage(in data: Data) -> String? {
        if let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error {
            return message
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
