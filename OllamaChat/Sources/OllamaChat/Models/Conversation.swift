import Foundation

enum Role: String, Codable {
    case system
    case user
    case assistant
}

struct GenerationStats: Codable, Equatable {
    var tokens: Int
    var seconds: Double

    var tokensPerSecond: Double? {
        seconds > 0 ? Double(tokens) / seconds : nil
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: Role
    var content: String
    /// Raisonnement renvoyé à part par les modèles « thinking » (champ `thinking` de l’API).
    var thinking: String
    var createdAt: Date
    var model: String?
    var stats: GenerationStats?
    var errorText: String?

    init(role: Role, content: String, model: String? = nil) {
        id = UUID()
        self.role = role
        self.content = content
        thinking = ""
        createdAt = Date()
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, thinking, createdAt, model, stats, errorText
    }

    // Décodage tolérant : un champ absent (fichier d’une version antérieure) prend sa valeur par défaut.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        model = try container.decodeIfPresent(String.self, forKey: .model)
        stats = try container.decodeIfPresent(GenerationStats.self, forKey: .stats)
        errorText = try container.decodeIfPresent(String.self, forKey: .errorText)
    }
}

struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var model: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(title: String, model: String) {
        id = UUID()
        self.title = title
        self.model = model
        messages = []
        createdAt = Date()
        updatedAt = createdAt
    }
}

/// Sépare un éventuel bloc `<think>…</think>` placé au début de la réponse
/// (anciennes versions d’Ollama ou modèles qui l’écrivent directement dans le texte).
enum ThinkingParser {
    struct Result {
        var thinking: String
        var answer: String
    }

    static func split(_ content: String) -> Result {
        let start = content.drop(while: { $0.isWhitespace })
        guard start.hasPrefix("<think>") else {
            return Result(thinking: "", answer: content)
        }
        let inside = start.dropFirst("<think>".count)
        guard let close = inside.range(of: "</think>") else {
            return Result(thinking: trimmed(inside), answer: "")
        }
        return Result(
            thinking: trimmed(inside[..<close.lowerBound]),
            answer: trimmed(inside[close.upperBound...])
        )
    }

    private static func trimmed(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
