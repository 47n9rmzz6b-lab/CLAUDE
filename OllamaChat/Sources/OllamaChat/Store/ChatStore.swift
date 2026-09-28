import AppKit
import Foundation
import Observation

/// État de l’application : conversations, modèles disponibles, génération en cours.
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
    var connection: Connection = .unknown
    var generatingID: Conversation.ID?
    /// Modèle choisi sur l’écran « Nouvelle conversation ».
    var draftModel = ""
    var showModelManager = false
    var pull: PullState?
    var modelError: String?

    /// La sélection vient de changer au clavier dans la barre latérale (flèches) : la zone de saisie
    /// ne prend alors pas le focus, pour qu’on puisse continuer à parcourir la liste.
    @ObservationIgnored var selectionChangedWithKeyboard = false

    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var pullTask: Task<Void, Never>?
    private let storeURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = support.appending(path: "OllamaChat", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appending(path: "conversations.json", directoryHint: .notDirectory)
        conversations = Self.load(from: storeURL)
        draftModel = UserDefaults.standard.string(forKey: SettingsKey.defaultModel) ?? ""
        // Rouvre la conversation affichée lors de la dernière utilisation.
        if let last = UserDefaults.standard.string(forKey: SettingsKey.lastConversationID),
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

    var canRegenerate: Bool {
        !isGenerating && selectedConversation?.messages.last?.role == .assistant
    }

    var serverAddress: String {
        UserDefaults.standard.string(forKey: SettingsKey.serverURL) ?? AppDefaults.serverURL
    }

    // MARK: - Conversations

    func newConversation() {
        selectionChangedWithKeyboard = false
        selectedID = nil
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: id) else { return }
        conversations[index].title = trimmed
        save()
    }

    func delete(_ id: UUID) {
        if generatingID == id { stopGeneration() }
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        save()
    }

    func selectModel(_ name: String) {
        draftModel = name
        UserDefaults.standard.set(name, forKey: SettingsKey.defaultModel)
        if let selectedID, let index = index(of: selectedID) {
            conversations[index].model = name
            save()
        }
    }

    // MARK: - Génération

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        let conversationID: UUID
        if let selectedID, index(of: selectedID) != nil {
            conversationID = selectedID
        } else {
            let conversation = Conversation(title: Self.makeTitle(from: text), model: currentModel)
            conversations.insert(conversation, at: 0)
            selectionChangedWithKeyboard = false
            selectedID = conversation.id
            conversationID = conversation.id
        }
        guard let index = index(of: conversationID) else { return }
        conversations[index].messages.append(ChatMessage(role: .user, content: text))
        conversations[index].updatedAt = Date()
        save()
        generate(in: conversationID)
    }

    func regenerate() {
        guard canRegenerate, let selectedID, let index = index(of: selectedID) else { return }
        conversations[index].messages.removeLast()
        generate(in: selectedID)
    }

    func stopGeneration() {
        generationTask?.cancel()
    }

    private func generate(in conversationID: UUID) {
        guard let index = index(of: conversationID) else { return }
        let model = conversations[index].model
        let history = requestMessages(for: conversations[index])
        let assistant = ChatMessage(role: .assistant, content: "", model: model)
        conversations[index].messages.append(assistant)

        let messageID = assistant.id

        guard !model.isEmpty else {
            updateMessage(messageID, in: conversationID) {
                $0.errorText = "Aucun modèle sélectionné. Choisissez-en un dans le menu sous la zone de saisie, ou téléchargez-en un depuis « Gérer les modèles »."
            }
            save()
            return
        }

        let client: OllamaClient
        do {
            client = try makeClient()
        } catch {
            let text = describe(error)
            updateMessage(messageID, in: conversationID) { $0.errorText = text }
            save()
            return
        }

        let options = currentOptions()
        generatingID = conversationID
        generationTask = Task { [weak self] in
            await self?.streamReply(
                client: client, model: model, history: history, options: options,
                conversationID: conversationID, messageID: messageID
            )
        }
    }

    private func streamReply(
        client: OllamaClient,
        model: String,
        history: [OllamaClient.Message],
        options: OllamaClient.Options?,
        conversationID: UUID,
        messageID: UUID
    ) async {
        do {
            for try await chunk in client.chat(model: model, messages: history, options: options) {
                let thinking = chunk.message?.thinking ?? ""
                let content = chunk.message?.content ?? ""
                if !thinking.isEmpty || !content.isEmpty {
                    updateMessage(messageID, in: conversationID) { message in
                        message.thinking += thinking
                        message.content += content
                    }
                }
                if chunk.done == true, let tokens = chunk.evalCount, let duration = chunk.evalDuration {
                    updateMessage(messageID, in: conversationID) { message in
                        message.stats = GenerationStats(tokens: tokens, seconds: Double(duration) / 1_000_000_000)
                    }
                }
            }
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                let text = describe(error)
                updateMessage(messageID, in: conversationID) { $0.errorText = text }
            }
        }

        if let index = index(of: conversationID) {
            conversations[index].updatedAt = Date()
        }
        generatingID = nil
        generationTask = nil
        save()
    }

    /// Historique envoyé au modèle : instructions système, puis les messages sans le raisonnement.
    private func requestMessages(for conversation: Conversation) -> [OllamaClient.Message] {
        var result: [OllamaClient.Message] = []
        let system = (UserDefaults.standard.string(forKey: SettingsKey.systemPrompt) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            result.append(.init(role: Role.system.rawValue, content: system))
        }
        for message in conversation.messages {
            let content = message.role == .assistant ? ThinkingParser.split(message.content).answer : message.content
            // Une réponse vide (erreur, arrêt immédiat) n’apporte rien au modèle.
            if message.role == .assistant && content.isEmpty { continue }
            result.append(.init(role: message.role.rawValue, content: content))
        }
        return result
    }

    private func currentOptions() -> OllamaClient.Options? {
        let defaults = UserDefaults.standard
        var options = OllamaClient.Options()
        if defaults.bool(forKey: SettingsKey.useCustomTemperature) {
            options.temperature = defaults.double(forKey: SettingsKey.temperature)
        }
        let contextLength = defaults.integer(forKey: SettingsKey.contextLength)
        if contextLength > 0 {
            options.numCtx = contextLength
        }
        return options.isEmpty ? nil : options
    }

    private func updateMessage(_ messageID: UUID, in conversationID: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let conversationIndex = index(of: conversationID),
              let messageIndex = conversations[conversationIndex].messages.lastIndex(where: { $0.id == messageID })
        else { return }
        change(&conversations[conversationIndex].messages[messageIndex])
    }

    // MARK: - Modèles et connexion

    /// Interroge Ollama régulièrement : la liste des modèles reste à jour (y compris après un
    /// `ollama pull` fait dans le Terminal) et l’app se reconnecte seule quand Ollama démarre.
    func monitorConnection() async {
        while !Task.isCancelled {
            await refreshModels()
            let delay: Duration = isConnected ? .seconds(20) : .seconds(4)
            try? await Task.sleep(for: delay)
        }
    }

    func refreshModels() async {
        do {
            let list = try await makeClient().listModels()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if models != list { models = list }
            if connection != .connected { connection = .connected }
            if !list.contains(where: { $0.name == draftModel }), let first = list.first {
                draftModel = first.name
            }
        } catch {
            let message = describe(error)
            if connection != .unreachable(message) { connection = .unreachable(message) }
            if !models.isEmpty { models = [] }
        }
    }

    func pullModel(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, pull?.isActive != true else { return }
        modelError = nil
        pull = PullState(model: name, status: "Connexion…")
        pullTask = Task { [weak self] in
            await self?.runPull(name)
        }
    }

    func cancelPull() {
        pullTask?.cancel()
        pullTask = nil
        pull = nil
    }

    func dismissPullStatus() {
        if pull?.isActive != true { pull = nil }
    }

    private func runPull(_ name: String) async {
        do {
            let client = try makeClient()
            for try await progress in client.pull(model: name) {
                guard var state = pull, state.model == name else { return }
                if let status = progress.status { state.status = Self.pullStatusText(status) }
                if let total = progress.total, total > 0 {
                    state.total = total
                    state.completed = progress.completed ?? 0
                }
                pull = state
            }
            guard !Task.isCancelled else { return }
            pull?.isFinished = true
            pull?.status = "Le modèle est installé et prêt à l’emploi."
            await refreshModels()
        } catch {
            guard !Task.isCancelled else { return }
            pull?.error = describe(error)
        }
        pullTask = nil
    }

    func deleteModel(_ name: String) async {
        modelError = nil
        do {
            try await makeClient().deleteModel(name)
        } catch {
            modelError = describe(error)
        }
        await refreshModels()
    }

    /// Emplacement de l’application Ollama, si elle est installée.
    static var ollamaAppURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") {
            return url
        }
        return ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    func launchOllama() {
        guard let url = Self.ollamaAppURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        Task {
            try? await Task.sleep(for: .seconds(3))
            await refreshModels()
        }
    }

    // MARK: - Outils

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

    private func makeClient() throws -> OllamaClient {
        try OllamaClient(address: serverAddress)
    }

    private func index(of id: UUID) -> Int? {
        conversations.firstIndex { $0.id == id }
    }

    private static func makeTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let title = firstLine.trimmingCharacters(in: .whitespaces)
        guard title.count > 48 else { return title }
        return title.prefix(48).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func pullStatusText(_ status: String) -> String {
        switch status {
        case "pulling manifest": return "Récupération du manifeste…"
        case "verifying sha256 digest": return "Vérification…"
        case "writing manifest": return "Écriture du manifeste…"
        case "removing any unused layers", "removing unused layers": return "Nettoyage…"
        case "success": return "Terminé"
        default:
            if status.hasPrefix("pulling") || status.hasPrefix("downloading") { return "Téléchargement…" }
            return status
        }
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
