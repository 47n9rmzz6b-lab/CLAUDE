import Foundation

/// Envoi des messages et génération des réponses.
extension ChatStore {
    // MARK: - Actions

    /// Envoie un message. `images` : pièces jointes à envoyer avec (par défaut, celles en attente).
    func send(_ rawText: String, images: [String]? = nil) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = images ?? pendingImages
        guard !text.isEmpty || !images.isEmpty, !isGenerating else { return }

        let conversationID: UUID
        if let selectedID, index(of: selectedID) != nil {
            conversationID = selectedID
        } else {
            var conversation = Conversation(
                title: Self.makeTitle(from: text.isEmpty ? "Image" : text),
                model: currentModel,
                profileID: draftProfileID,
                thinking: draftThinking,
                webSearch: draftWebSearch
            )
            conversation.documents = draftDocuments
            draftDocuments = []
            conversations.insert(conversation, at: 0)
            selectionChangedWithKeyboard = false
            selectedID = conversation.id
            conversationID = conversation.id
        }
        guard let index = index(of: conversationID) else { return }
        let message = ChatMessage(role: .user, content: text, images: images)
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        pendingImages.removeAll { images.contains($0) }
        handleMemoryCommand(in: text, conversationID: conversationID, messageID: message.id)
        save()
        generate(in: conversationID)
    }

    func regenerate() {
        guard canRegenerate, let selectedID, let index = index(of: selectedID) else { return }
        conversations[index].messages.removeLast()
        generate(in: selectedID)
    }

    /// Demande au modèle de relire et vérifier sa dernière réponse.
    func verifyLastAnswer() {
        guard canRegenerate, let selectedID, let index = index(of: selectedID) else { return }
        conversations[index].messages.append(
            ChatMessage(role: .user, content: PromptBuilder.verificationRequest, kind: .verification)
        )
        conversations[index].updatedAt = Date()
        save()
        generate(in: selectedID)
    }

    func stopGeneration() {
        generationTask?.cancel()
    }

    // MARK: - Contexte

    /// Taille de contexte envoyée à Ollama pour une conversation (`nil` : valeur par défaut d’Ollama).
    func contextLength(model: String, webSearch: Bool, hasDocuments: Bool) -> Int? {
        let setting = UserDefaults.standard.integer(forKey: SettingsKey.contextLength)
        guard setting > 0 else { return nil }
        var length = setting
        if webSearch || hasDocuments {
            length = max(length, AppDefaults.contextLengthWithTools)
        }
        if let maximum = info(for: model).maxContextLength, maximum > 0 {
            length = min(length, maximum)
        }
        return length
    }

    /// Nombre de jetons estimé de ce qui sera envoyé au modèle (hors réponse à venir).
    func estimatedPromptTokens(for conversation: Conversation?, draft: String = "") -> Int {
        let context = promptContext(
            profileID: conversation?.profileID ?? draftProfileID,
            webSearch: conversation?.webSearch ?? draftWebSearch,
            model: conversation?.model ?? draftModel,
            documents: conversation?.documents ?? []
        )
        var total = TokenEstimator.tokens(in: PromptBuilder.systemPrompt(context) ?? "")
        for message in conversation?.messages ?? [] {
            let content = message.role == .assistant ? ThinkingParser.split(message.content).answer : message.content
            total += TokenEstimator.tokens(in: content) + TokenEstimator.tokensPerMessage
            total += message.images.count * TokenEstimator.tokensPerImage
        }
        if let documents = conversation?.documents, !documents.isEmpty {
            total += DocumentService.excerptBudgetTokens(for: documents)
        }
        total += TokenEstimator.tokens(in: draft)
        return total
    }

    // MARK: - Génération

    func generate(in conversationID: UUID) {
        guard let index = index(of: conversationID) else { return }
        let conversation = conversations[index]
        let model = conversation.model
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

        let request = makeRequest(for: conversation)
        generatingID = conversationID
        generationTask = Task { [weak self] in
            await self?.streamReply(client: client, request: request, conversationID: conversationID, messageID: messageID)
            await self?.didFinishReply(in: conversationID, messageID: messageID)
        }
    }

    /// Tout ce qu’il faut pour interroger le modèle.
    struct ReplyRequest {
        var model: String
        var history: [OllamaClient.Message]
        var options: OllamaClient.Options?
        var think: OllamaClient.Think?
        var webSearch: WebSearchMode
        var documents: [DocumentRef]
        /// Texte de la dernière question, pour la recherche web préalable et les documents.
        var question: String
    }

    func promptContext(profileID: String, webSearch: Bool, model: String, documents: [DocumentRef]) -> PromptContext {
        let defaults = UserDefaults.standard
        var context = PromptContext(profile: ResponseProfile.profile(id: profileID))
        context.aboutMe = defaults.string(forKey: SettingsKey.aboutMe) ?? ""
        context.responseStyle = defaults.string(forKey: SettingsKey.responseStyle) ?? ""
        context.memories = memoriesForPrompt()
        context.webSearch = webSearch ? webSearchMode(for: model) : .none
        context.documentNames = documents.filter { $0.status == .ready }.map(\.name)
        return context
    }

    func makeRequest(for conversation: Conversation) -> ReplyRequest {
        let model = conversation.model
        let modelInfo = info(for: model)
        let readyDocuments = conversation.documents.filter { $0.status == .ready }
        let context = promptContext(
            profileID: conversation.profileID,
            webSearch: conversation.webSearch,
            model: model,
            documents: readyDocuments
        )

        var history: [OllamaClient.Message] = []
        if let system = PromptBuilder.systemPrompt(context) {
            history.append(.init(role: Role.system.rawValue, content: system))
        }
        // Les images coûtent cher à chaque requête : seules les plus récentes sont renvoyées.
        var imageBudget = 4
        var messages: [OllamaClient.Message] = []
        for message in conversation.messages.reversed() {
            let content = message.role == .assistant ? ThinkingParser.split(message.content).answer : message.content
            // Une réponse vide (erreur, arrêt immédiat) n’apporte rien au modèle.
            if message.role == .assistant && content.isEmpty { continue }
            var images: [String]?
            if modelInfo.supportsVision, !message.images.isEmpty, imageBudget > 0 {
                let encoded = message.images.prefix(imageBudget).compactMap { AttachmentStore.shared.base64(for: $0) }
                imageBudget -= encoded.count
                images = encoded.isEmpty ? nil : encoded
            }
            messages.append(.init(role: message.role.rawValue, content: content, images: images))
        }
        history.append(contentsOf: messages.reversed())

        let question = conversation.messages.last(where: { $0.role == .user && $0.kind == .normal })?.content ?? ""

        var options = OllamaClient.Options()
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: SettingsKey.useCustomTemperature) {
            options.temperature = defaults.double(forKey: SettingsKey.temperature)
        } else {
            options.temperature = context.profile.temperature
        }
        options.numCtx = contextLength(model: model, webSearch: conversation.webSearch, hasDocuments: !readyDocuments.isEmpty)

        return ReplyRequest(
            model: model,
            history: history,
            options: options.isEmpty ? nil : options,
            think: thinkParameter(for: model, setting: conversation.thinking),
            webSearch: context.webSearch,
            documents: readyDocuments,
            question: question
        )
    }

    /// Valeur du paramètre `think` pour ce modèle, ou `nil` s’il ne sait pas raisonner.
    func thinkParameter(for model: String, setting: ThinkingSetting) -> OllamaClient.Think? {
        let modelInfo = info(for: model)
        guard modelInfo.supportsThinking else { return nil }
        if modelInfo.usesThinkingLevels {
            switch setting {
            case .low, .off: return .level("low")
            case .high: return .level("high")
            case .medium, .on: return .level("medium")
            }
        }
        return .enabled(setting != .off)
    }

    /// Diffuse la réponse du modèle dans le message `messageID`. Gère la réflexion, les outils
    /// de recherche web (plusieurs allers-retours) et les extraits de documents.
    func streamReply(client: OllamaClient, request: ReplyRequest, conversationID: UUID, messageID: UUID) async {
        var history = request.history
        do {
            history = try await prepareContext(history: history, request: request, conversationID: conversationID, messageID: messageID)

            let tools = request.webSearch == .tools ? WebSearchService.tools : nil
            var round = 0
            var thinkingStart: Date?
            var thinkingMeasured = false

            while true {
                round += 1
                let offerTools = tools != nil && round <= WebSearchService.maxRounds
                var toolCalls: [ToolCall] = []
                var roundContent = ""
                let contentBefore = conversation(conversationID)?.messages.first { $0.id == messageID }?.content ?? ""

                for try await chunk in client.chat(
                    model: request.model,
                    messages: history,
                    options: request.options,
                    think: request.think,
                    tools: offerTools ? tools : nil
                ) {
                    let thinking = chunk.message?.thinking ?? ""
                    let content = chunk.message?.content ?? ""
                    if !thinking.isEmpty, thinkingStart == nil { thinkingStart = Date() }
                    if !content.isEmpty, let start = thinkingStart, !thinkingMeasured {
                        thinkingMeasured = true
                        let seconds = Date().timeIntervalSince(start)
                        updateMessage(messageID, in: conversationID) { $0.thinkingSeconds = seconds }
                    }
                    if !thinking.isEmpty || !content.isEmpty {
                        roundContent += content
                        updateMessage(messageID, in: conversationID) { message in
                            message.thinking += thinking
                            message.content += content
                            // Réflexion écrite entre balises <think> dans le texte.
                            if message.thinkingSeconds == nil, message.content.contains("</think>"), let start = thinkingStart ?? Optional(message.createdAt) {
                                message.thinkingSeconds = Date().timeIntervalSince(start)
                            }
                        }
                    }
                    if let calls = chunk.message?.toolCalls { toolCalls.append(contentsOf: calls) }
                    if chunk.done == true, let tokens = chunk.evalCount, let duration = chunk.evalDuration {
                        updateMessage(messageID, in: conversationID) { message in
                            message.stats = GenerationStats(tokens: tokens, seconds: Double(duration) / 1_000_000_000)
                        }
                    }
                }

                guard !toolCalls.isEmpty, offerTools, !Task.isCancelled else { break }
                // Le texte écrit avant un appel d’outil (« je vais chercher… ») n’est pas conservé.
                updateMessage(messageID, in: conversationID) { $0.content = contentBefore }
                history.append(.init(role: Role.assistant.rawValue, content: roundContent, toolCalls: toolCalls))
                for call in toolCalls {
                    let result = await runTool(call, conversationID: conversationID, messageID: messageID)
                    history.append(.init(role: "tool", content: result, toolName: call.function.name))
                }
            }
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                let text = describe(error)
                updateMessage(messageID, in: conversationID) { $0.errorText = text }
            }
        }
        updateMessage(messageID, in: conversationID) { message in
            for index in message.steps.indices { message.steps[index].isRunning = false }
        }
    }

    /// Fin d’une réponse : enregistrement, titre automatique, mémoire.
    func didFinishReply(in conversationID: UUID, messageID: UUID) async {
        if let index = index(of: conversationID) {
            conversations[index].updatedAt = Date()
        }
        generatingID = nil
        generationTask = nil
        save()
        await afterReply(in: conversationID, messageID: messageID)
    }
}
