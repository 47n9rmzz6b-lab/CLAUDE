import AppKit
import Foundation
import Observation

/// État de l’application : conversations, modèles disponibles, génération en cours.
/// La génération, les modèles, la mémoire, la recherche web et les documents sont
/// traités dans des extensions (fichiers `ChatStore+…`).
@MainActor
@Observable
final class ChatStore {
    enum Connection: Equatable {
        case unknown
        case connected
        case unreachable(String)
    }

    struct PullState: Equatable {
        var model: String
        var status: String
        var completed: Int64 = 0
        var total: Int64 = 0
        var error: String?
        var isFinished = false

        var isActive: Bool { !isFinished && error == nil }

        var fraction: Double? {
            guard total > 0 else { return nil }
            return min(1, Double(completed) / Double(total))
        }
    }

    var conversations: [Conversation] = []
    /// `nil` : écran « Nouvelle conversation » (la conversation est créée au premier message).
    var selectedID: Conversation.ID?
    var models: [OllamaModel] = []
    /// Capacités des modèles installés (réflexion, outils, vision, indexation).
    var modelInfo: [String: ModelInfo] = [:]
    var connection: Connection = .unknown
    var generatingID: Conversation.ID?
    var showModelManager = false
    var pull: PullState?
    var modelError: String?

    // Réglages de l’écran « Nouvelle conversation », repris de la dernière conversation utilisée.
    var draftModel = ""
    var draftProfileID = ResponseProfile.balanced.id
    var draftThinking = ThinkingSetting.on
    var draftWebSearch = false
    /// Documents joints avant le premier message d’une nouvelle conversation.
    var draftDocuments: [DocumentRef] = []

    /// Images prêtes à partir avec le prochain message.
    var pendingImages: [String] = []
    var attachmentError: String?
    /// Message de l’utilisateur en cours de modification.
    var editingMessageID: UUID?

    let memory = MemoryStore()
    let dictation = DictationController()

    /// La sélection vient de changer au clavier dans la barre latérale (flèches) : la zone de saisie
    /// ne prend alors pas le focus, pour qu’on puisse continuer à parcourir la liste.
    @ObservationIgnored var selectionChangedWithKeyboard = false

    @ObservationIgnored var generationTask: Task<Void, Never>?
    @ObservationIgnored var pullTask: Task<Void, Never>?
    @ObservationIgnored var modelInfoDigests: [String: String] = [:]
    @ObservationIgnored var memoryTask: Task<Void, Never>?
    @ObservationIgnored var pendingMemoryConversations: [UUID] = []
    @ObservationIgnored var launchMemoryScanDone = false
    @ObservationIgnored var webSearchConfiguredCache: (date: Date, value: Bool)?
    let storeURL: URL

    init() {
        let directory = AppPaths.support
        storeURL = directory.appending(path: "conversations.json", directoryHint: .notDirectory)
        conversations = Self.load(from: storeURL)

        let defaults = UserDefaults.standard
        draftModel = defaults.string(forKey: SettingsKey.defaultModel) ?? ""
        draftProfileID = defaults.string(forKey: SettingsKey.lastProfileID) ?? ResponseProfile.balanced.id
        draftThinking = ThinkingSetting(rawValue: defaults.string(forKey: SettingsKey.lastThinking) ?? "") ?? .on
        draftWebSearch = defaults.bool(forKey: SettingsKey.lastWebSearch)

        // Rouvre la conversation affichée lors de la dernière utilisation.
        if let last = defaults.string(forKey: SettingsKey.lastConversationID),
           let id = UUID(uuidString: last),
           conversations.contains(where: { $0.id == id }) {
            selectedID = id
        }
    }

    // MARK: - État dérivé

    var isGenerating: Bool { generatingID != nil }
    var isConnected: Bool { connection == .connected }

    var selectedConversation: Conversation? {
        guard let selectedID else { return nil }
        return conversations.first { $0.id == selectedID }
    }

    var currentModel: String { selectedConversation?.model ?? draftModel }
    var currentProfile: ResponseProfile { ResponseProfile.profile(id: selectedConversation?.profileID ?? draftProfileID) }
    var currentThinking: ThinkingSetting { selectedConversation?.thinking ?? draftThinking }
    var currentWebSearch: Bool { selectedConversation?.webSearch ?? draftWebSearch }

    var canRegenerate: Bool {
        !isGenerating && selectedConversation?.messages.last?.role == .assistant
    }

    var serverAddress: String {
        UserDefaults.standard.string(forKey: SettingsKey.serverURL) ?? AppDefaults.serverURL
    }

    // MARK: - Conversations

    func newConversation() {
        selectionChangedWithKeyboard = false
        editingMessageID = nil
        selectedID = nil
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: id) else { return }
        conversations[index].title = trimmed
        conversations[index].titleIsCustom = true
        save()
    }

    func delete(_ id: UUID) {
        if generatingID == id { stopGeneration() }
        if let conversation = conversations.first(where: { $0.id == id }) {
            AttachmentStore.shared.removeFiles(of: conversation)
        }
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        save()
    }

    func selectModel(_ name: String) {
        draftModel = name
        UserDefaults.standard.set(name, forKey: SettingsKey.defaultModel)
        updateSelected { $0.model = name }
    }

    func selectProfile(_ id: String) {
        draftProfileID = id
        UserDefaults.standard.set(id, forKey: SettingsKey.lastProfileID)
        updateSelected { $0.profileID = id }
    }

    func setThinking(_ setting: ThinkingSetting) {
        draftThinking = setting
        UserDefaults.standard.set(setting.rawValue, forKey: SettingsKey.lastThinking)
        updateSelected { $0.thinking = setting }
    }

    func setWebSearch(_ enabled: Bool) {
        draftWebSearch = enabled
        UserDefaults.standard.set(enabled, forKey: SettingsKey.lastWebSearch)
        updateSelected { $0.webSearch = enabled }
    }

    /// Modifie la conversation affichée (s’il y en a une) et l’enregistre.
    func updateSelected(_ change: (inout Conversation) -> Void) {
        guard let selectedID, let index = index(of: selectedID) else { return }
        change(&conversations[index])
        save()
    }

    func updateMessage(_ messageID: UUID, in conversationID: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let conversationIndex = index(of: conversationID),
              let messageIndex = conversations[conversationIndex].messages.lastIndex(where: { $0.id == messageID })
        else { return }
        change(&conversations[conversationIndex].messages[messageIndex])
    }

    func index(of id: UUID) -> Int? {
        conversations.firstIndex { $0.id == id }
    }

    func conversation(_ id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    static func makeTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let title = firstLine.trimmingCharacters(in: .whitespaces)
        guard title.count > 48 else { return title.isEmpty ? "Nouvelle conversation" : title }
        return title.prefix(48).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Erreurs

    func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
                return "Impossible de joindre Ollama à \(serverAddress). Ouvrez l’application Ollama, ou lancez « ollama serve » dans le Terminal."
            case .timedOut:
                return "Ollama ne répond pas (délai dépassé)."
            default:
                return urlError.localizedDescription
            }
        }
        if let description = (error as? LocalizedError)?.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    func makeClient() throws -> OllamaClient {
        try OllamaClient(address: serverAddress)
    }

    // MARK: - Persistance

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(conversations)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("OllamaChat : échec de l’enregistrement des conversations : \(error)")
        }
    }

    private static func load(from url: URL) -> [Conversation] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([Conversation].self, from: data)
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            // Fichier illisible : on le met de côté plutôt que de l’écraser au prochain enregistrement.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("illisible-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("OllamaChat : conversations illisibles, copie conservée dans \(backup.path(percentEncoded: false))")
            return []
        }
    }
}
