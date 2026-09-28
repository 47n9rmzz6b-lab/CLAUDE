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

/// Nature d’un message de l’utilisateur.
enum MessageKind: String, Codable {
    case normal
    /// Demande de vérification de la réponse précédente (bouton « Vérifier »).
    case verification
}

/// Réglage de réflexion d’une conversation, pour les modèles qui savent raisonner.
enum ThinkingSetting: String, Codable, CaseIterable {
    case on
    case off
    /// Niveaux proposés par gpt-oss, qui ne peut pas désactiver sa réflexion.
    case low
    case medium
    case high
}

/// Étape visible pendant la préparation d’une réponse : recherche web, lecture d’une page,
/// consultation des documents joints.
struct ToolStep: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case search
        case fetch
        case documents
    }

    var id = UUID()
    var kind: Kind
    var detail: String
    var resultCount: Int?
    var isRunning = false
    var error: String?
}

/// Source citable dans une réponse : résultat web ([1], [2]…) ou passage d’un document ([D1]…).
struct Source: Codable, Equatable, Identifiable, Hashable {
    var tag: String
    var title: String
    var url: String?
    var detail: String?

    var id: String { tag }
}

/// Document joint à une conversation. Son texte découpé (et, si possible, ses vecteurs)
/// est enregistré à part, dans le dossier des pièces jointes.
struct DocumentRef: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        case indexing
        case ready
        case failed
    }

    var id = UUID()
    var name: String
    var characterCount: Int = 0
    var chunkCount: Int = 0
    var pageCount: Int?
    /// Modèle ayant calculé les vecteurs des passages ; `nil` : recherche par mots-clés.
    var embeddingModel: String?
    var status: Status = .indexing
    var error: String?
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
    var kind: MessageKind
    /// Durée de la réflexion, en secondes.
    var thinkingSeconds: Double?
    /// Images jointes : noms de fichiers dans le dossier des pièces jointes.
    var images: [String]
    var steps: [ToolStep]
    var sources: [Source]
    /// La mémoire a été mise à jour à partir de cet échange.
    var memoryUpdated: Bool

    init(role: Role, content: String, model: String? = nil, kind: MessageKind = .normal, images: [String] = []) {
        id = UUID()
        self.role = role
        self.content = content
        thinking = ""
        createdAt = Date()
        self.model = model
        self.kind = kind
        self.images = images
        steps = []
        sources = []
        memoryUpdated = false
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, thinking, createdAt, model, stats, errorText
        case kind, thinkingSeconds, images, steps, sources, memoryUpdated
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
        kind = try container.decodeIfPresent(MessageKind.self, forKey: .kind) ?? .normal
        thinkingSeconds = try container.decodeIfPresent(Double.self, forKey: .thinkingSeconds)
        images = try container.decodeIfPresent([String].self, forKey: .images) ?? []
        steps = try container.decodeIfPresent([ToolStep].self, forKey: .steps) ?? []
        sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
        memoryUpdated = try container.decodeIfPresent(Bool.self, forKey: .memoryUpdated) ?? false
    }
}

struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var model: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    /// Titre choisi par l’utilisateur : il n’est plus remplacé automatiquement.
    var titleIsCustom: Bool
    /// Un titre a déjà été proposé par le modèle.
    var titleGenerated: Bool
    var profileID: String
    var thinking: ThinkingSetting
    var webSearch: Bool
    var documents: [DocumentRef]
    /// Nombre de messages déjà examinés pour en tirer des souvenirs.
    var memoryProcessedCount: Int

    init(
        title: String,
        model: String,
        profileID: String = ResponseProfile.balanced.id,
        thinking: ThinkingSetting = .on,
        webSearch: Bool = false
    ) {
        id = UUID()
        self.title = title
        self.model = model
        messages = []
        createdAt = Date()
        updatedAt = createdAt
        titleIsCustom = false
        titleGenerated = false
        self.profileID = profileID
        self.thinking = thinking
        self.webSearch = webSearch
        documents = []
        memoryProcessedCount = 0
    }

    enum CodingKeys: String, CodingKey {
        case id, title, model, messages, createdAt, updatedAt
        case titleIsCustom, titleGenerated, profileID, thinking, webSearch, documents, memoryProcessedCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Conversation"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        titleIsCustom = try container.decodeIfPresent(Bool.self, forKey: .titleIsCustom) ?? false
        // Les conversations antérieures gardent leur titre.
        titleGenerated = try container.decodeIfPresent(Bool.self, forKey: .titleGenerated) ?? true
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID) ?? ResponseProfile.balanced.id
        thinking = try container.decodeIfPresent(ThinkingSetting.self, forKey: .thinking) ?? .on
        webSearch = try container.decodeIfPresent(Bool.self, forKey: .webSearch) ?? false
        documents = try container.decodeIfPresent([DocumentRef].self, forKey: .documents) ?? []
        // Les conversations antérieures ne sont pas relues pour la mémoire.
        memoryProcessedCount = try container.decodeIfPresent(Int.self, forKey: .memoryProcessedCount) ?? messages.count
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
