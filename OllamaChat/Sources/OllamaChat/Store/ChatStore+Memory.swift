import Foundation

/// Mémoire (souvenirs sur l’utilisateur) et titres automatiques.
extension ChatStore {
    var memoryEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.memoryEnabled) }
    var memoryAutoExtract: Bool { UserDefaults.standard.bool(forKey: SettingsKey.memoryAutoExtract) }

    func memoriesForPrompt() -> [String] {
        memoryEnabled ? memory.textsForPrompt().map(MemoryText.forPrompt) : []
    }

    /// « Retiens que… » / « Oublie… » au début d’un message : la mémoire est mise à jour
    /// tout de suite, et le message part quand même au modèle.
    func handleMemoryCommand(in text: String, conversationID: UUID, messageID: UUID) {
        guard memoryEnabled, let command = MemoryCommand.parse(text) else { return }
        var changed = false
        switch command {
        case .remember(let fact):
            changed = memory.add(fact, conversationID: conversationID)
        case .forget(let phrase):
            changed = memory.forget(matching: phrase) > 0
        }
        if changed {
            updateMessage(messageID, in: conversationID) { $0.memoryUpdated = true }
        }
    }

    /// Après chaque réponse : titre, puis souvenirs si la conversation s’est beaucoup allongée.
    func afterReply(in conversationID: UUID, messageID: UUID) async {
        await generateTitleIfNeeded(conversationID)
        if let conversation = conversation(conversationID),
           unprocessedUserMessages(in: conversation).count >= 4 {
            scheduleMemoryExtraction(for: [conversationID])
        }
    }

    /// Premier contact avec Ollama : on relit les conversations récentes pas encore examinées.
    func onConnected() {
        guard !launchMemoryScanDone else { return }
        launchMemoryScanDone = true
        let recent = conversations
            .filter { !unprocessedUserMessages(in: $0).isEmpty && $0.updatedAt > Date().addingTimeInterval(-7 * 24 * 3600) }
            .prefix(3)
            .map(\.id)
        scheduleMemoryExtraction(for: Array(recent))
    }

    /// On quitte une conversation : c’est le bon moment pour en tirer des souvenirs.
    func conversationDidChange(from previousID: UUID?) {
        guard let previousID else { return }
        scheduleMemoryExtraction(for: [previousID])
    }

    func unprocessedUserMessages(in conversation: Conversation) -> [ChatMessage] {
        let start = min(conversation.memoryProcessedCount, conversation.messages.count)
        return conversation.messages[start...].filter { $0.role == .user && $0.kind == .normal }
    }

    func scheduleMemoryExtraction(for ids: [UUID]) {
        guard memoryEnabled, memoryAutoExtract, !ids.isEmpty else { return }
        pendingMemoryConversations.append(contentsOf: ids.filter { !pendingMemoryConversations.contains($0) })
        guard memoryTask == nil else { return }
        memoryTask = Task { [weak self] in
            await self?.drainMemoryQueue()
        }
    }

    private func drainMemoryQueue() async {
        while !pendingMemoryConversations.isEmpty {
            // On laisse passer la réponse en cours : les deux se disputeraient le modèle.
            while isGenerating {
                try? await Task.sleep(for: .seconds(2))
            }
            let id = pendingMemoryConversations.removeFirst()
            await extractMemories(from: id)
        }
        memoryTask = nil
    }

    private static let memorySchema: JSONValue = [
        "type": "object",
        "properties": ["souvenirs": ["type": "array", "items": ["type": "string"]]],
        "required": ["souvenirs"],
    ]

    private static let memoryInstructions = """
    Tu aides un assistant à se souvenir de son utilisateur d’une conversation à l’autre. \
    À partir des messages de l’utilisateur ci-dessous, extrais uniquement les informations durables \
    et utiles le concernant : identité, métier, compétences, équipement, préférences, projets en cours, contraintes. \
    Ignore les questions ponctuelles, les sujets passagers et tout ce qui concerne d’autres personnes. \
    Chaque souvenir est une phrase courte et autonome, écrite à la troisième personne, \
    par exemple « L’utilisateur travaille comme infirmier. ». Ne répète pas un souvenir déjà enregistré. \
    S’il n’y a rien à retenir, renvoie une liste vide. Réponds uniquement en JSON.
    """

    func extractMemories(from conversationID: UUID) async {
        guard memoryEnabled, memoryAutoExtract, let conversation = conversation(conversationID) else { return }
        let messages = unprocessedUserMessages(in: conversation)
        let processedCount = conversation.messages.count
        guard !messages.isEmpty else {
            markMemoryProcessed(conversationID, count: processedCount)
            return
        }
        // Le modèle en cours d’utilisation, déjà chargé : un autre modèle pourrait l’évincer de la mémoire.
        let installed = Set(chatModels.map(\.name))
        let model = [currentModel, conversation.model, draftModel].first { installed.contains($0) } ?? ""
        guard !model.isEmpty, let client = try? makeClient() else { return }

        var userText = messages.map { "« \($0.content) »" }.joined(separator: "\n")
        if userText.count > 6000 { userText = String(userText.suffix(6000)) }
        let known = memory.memories.map { "- \($0.text)" }.joined(separator: "\n")
        let prompt = """
        Souvenirs déjà enregistrés :
        \(known.isEmpty ? "(aucun)" : known)

        Messages de l’utilisateur :
        \(userText)
        """
        do {
            let reply = try await client.complete(
                model: model,
                messages: [
                    .init(role: Role.system.rawValue, content: Self.memoryInstructions),
                    .init(role: Role.user.rawValue, content: prompt),
                ],
                // Même taille de contexte que la conversation en cours, sinon Ollama recharge le modèle ;
                // gpt-oss réfléchit toujours un peu : il lui faut plus de place pour répondre.
                options: OllamaClient.Options(
                    temperature: 0,
                    numCtx: model == currentModel ? contextLength(for: selectedConversation) : contextLength(for: conversation),
                    numPredict: info(for: model).usesThinkingLevels ? 1500 : 400
                ),
                think: thinkParameter(for: model, setting: .off),
                format: Self.memorySchema
            )
            var added = 0
            for fact in MemoryExtraction.parse(reply) where memory.add(fact, conversationID: conversationID) {
                added += 1
            }
            markMemoryProcessed(conversationID, count: processedCount)
            if added > 0, let index = index(of: conversationID),
               let last = conversations[index].messages.lastIndex(where: { $0.role == .assistant }) {
                conversations[index].messages[last].memoryUpdated = true
                save()
            }
        } catch {
            NSLog("OllamaChat : extraction des souvenirs impossible : \(error)")
        }
    }

    private func markMemoryProcessed(_ conversationID: UUID, count: Int) {
        guard let index = index(of: conversationID) else { return }
        conversations[index].memoryProcessedCount = count
        save()
    }

    // MARK: - Titres

    func generateTitleIfNeeded(_ conversationID: UUID) async {
        guard UserDefaults.standard.bool(forKey: SettingsKey.autoTitles),
              let conversation = conversation(conversationID),
              !conversation.titleIsCustom, !conversation.titleGenerated,
              let question = conversation.messages.first(where: { $0.role == .user })?.content,
              let answer = conversation.messages.first(where: { $0.role == .assistant && !$0.content.isEmpty })?.content,
              let client = try? makeClient()
        else { return }
        if let index = index(of: conversationID) { conversations[index].titleGenerated = true }

        let answerText = ThinkingParser.split(answer).answer
        let prompt = """
        Donne un titre très court (3 à 6 mots) à cette conversation, dans la langue de l’utilisateur. \
        Réponds uniquement par le titre, sans guillemets ni ponctuation finale.

        Utilisateur : \(question.prefix(1000))
        Assistant : \(answerText.prefix(1000))
        """
        do {
            let reply = try await client.complete(
                model: conversation.model,
                messages: [.init(role: Role.user.rawValue, content: prompt)],
                options: OllamaClient.Options(
                    temperature: 0.3,
                    numCtx: contextLength(for: conversation),
                    numPredict: info(for: conversation.model).usesThinkingLevels ? 800 : 40
                ),
                think: thinkParameter(for: conversation.model, setting: .off)
            )
            guard let title = TitleCleaner.clean(reply),
                  let index = index(of: conversationID),
                  !conversations[index].titleIsCustom
            else { return }
            conversations[index].title = title
            save()
        } catch {
            NSLog("OllamaChat : titre automatique impossible : \(error)")
        }
    }
}

/// Lecture de la réponse JSON de l’extraction de souvenirs.
enum MemoryExtraction {
    static func parse(_ reply: String) -> [String] {
        let text = ThinkingParser.split(reply).answer
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .array(let items)? = value["souvenirs"]
        else { return [] }
        return items.compactMap(\.stringValue)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 8 && $0.count <= 240 }
    }
}

/// Nettoyage du titre proposé par le modèle.
enum TitleCleaner {
    static func clean(_ reply: String) -> String? {
        var text = ThinkingParser.split(reply).answer
        text = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        for prefix in ["titre :", "titre:", "title:", "title :"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        text = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'«»“”*#`.")))
        guard text.count >= 2 else { return nil }
        return text.count > 60 ? String(text.prefix(60)).trimmingCharacters(in: .whitespaces) + "…" : text
    }
}
