import Foundation

/// Recherche web (outils du modèle ou recherche préalable) et extraits des documents joints.
extension ChatStore {
    /// Mode de recherche web selon ce que sait faire le modèle.
    func webSearchMode(for model: String) -> WebSearchMode {
        info(for: model).supportsTools ? .tools : .preSearch
    }

    /// Recherche web utilisable (clé API ou serveur renseigné). Mis en cache quelques secondes :
    /// la vue le consulte à chaque rafraîchissement et la clé est lue dans le trousseau.
    var webSearchConfigured: Bool {
        if let cached = webSearchConfiguredCache, Date().timeIntervalSince(cached.date) < 5 {
            return cached.value
        }
        let value = WebSearchService.current().isConfigured
        webSearchConfiguredCache = (Date(), value)
        return value
    }

    /// Ajoute les extraits de documents et, pour les modèles sans outils, les résultats
    /// d’une recherche préalable, devant la dernière question.
    func prepareContext(
        history: [OllamaClient.Message],
        request: ReplyRequest,
        conversationID: UUID,
        messageID: UUID
    ) async throws -> [OllamaClient.Message] {
        var history = history
        var preface: [String] = []

        if !request.documents.isEmpty, !request.question.isEmpty {
            // Un document joint à l’instant peut être encore en cours de lecture : on l’attend.
            var documents = request.documents
            let waiting = documents.contains { $0.status == .indexing }
            let stepID = addStep(.documents, detail: waiting ? "Lecture des documents…" : "Consultation des documents", in: conversationID, messageID: messageID)
            while true {
                let latest = conversation(conversationID)?.documents ?? []
                documents = request.documents.compactMap { document in latest.first { $0.id == document.id } }
                guard documents.contains(where: { $0.status == .indexing }) else { break }
                try await Task.sleep(for: .milliseconds(300))
            }
            documents = documents.filter { $0.status == .ready }
            let excerpts = await documentExcerpts(for: request.question, documents: documents)
            let sources = excerpts.map { excerpt -> Source in
                var detail = excerpt.isFullText ? "texte intégral" : nil
                if let page = excerpt.page { detail = "page \(page)" }
                return Source(tag: excerpt.tag, title: excerpt.documentName, url: nil, detail: detail)
            }
            updateMessage(messageID, in: conversationID) { message in
                message.sources.append(contentsOf: sources)
            }
            finishStep(stepID, detail: excerpts.isEmpty ? "Aucun passage trouvé" : "\(excerpts.count) passage\(excerpts.count > 1 ? "s" : "") retenu\(excerpts.count > 1 ? "s" : "")", count: excerpts.count, in: conversationID, messageID: messageID)
            if !excerpts.isEmpty { preface.append(DocumentService.format(excerpts)) }
        }

        if request.webSearch == .preSearch, !request.question.isEmpty {
            let query = String(request.question.prefix(200))
            let stepID = addStep(.search, detail: query, in: conversationID, messageID: messageID)
            do {
                let results = try await WebSearchService.current().search(query)
                let tagged = registerWebSources(results, in: conversationID, messageID: messageID)
                finishStep(stepID, detail: query, count: results.count, in: conversationID, messageID: messageID)
                preface.append(WebSearchService.formatResults(tagged, query: query))
            } catch {
                finishStep(stepID, detail: query, error: describe(error), in: conversationID, messageID: messageID)
            }
        }

        if !preface.isEmpty, let last = history.lastIndex(where: { $0.role == Role.user.rawValue }) {
            history[last].content = preface.joined(separator: "\n\n") + "\n\nQuestion de l’utilisateur :\n" + history[last].content
        }
        return history
    }

    /// Exécute un outil demandé par le modèle et renvoie le texte à lui transmettre.
    func runTool(_ call: ToolCall, conversationID: UUID, messageID: UUID) async -> String {
        let service = WebSearchService.current()
        switch call.function.name {
        case "web_search":
            let query = (call.function.arguments["query"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return "Requête vide." }
            let stepID = addStep(.search, detail: query, in: conversationID, messageID: messageID)
            do {
                let results = try await service.search(query)
                let tagged = registerWebSources(results, in: conversationID, messageID: messageID)
                finishStep(stepID, detail: query, count: results.count, in: conversationID, messageID: messageID)
                return WebSearchService.formatResults(tagged, query: query)
            } catch {
                let text = describe(error)
                finishStep(stepID, detail: query, error: text, in: conversationID, messageID: messageID)
                return "La recherche a échoué : \(text)"
            }
        case "web_fetch":
            let address = (call.function.arguments["url"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let host = URL(string: address)?.host() ?? address
            let stepID = addStep(.fetch, detail: host, in: conversationID, messageID: messageID)
            do {
                let page = try await service.fetch(address)
                let tag = registerWebSources([WebResult(title: page.title, url: address, content: "")], in: conversationID, messageID: messageID).first?.tag ?? "?"
                finishStep(stepID, detail: host, count: nil, in: conversationID, messageID: messageID)
                return "Contenu de la page [\(tag)] « \(page.title) » (\(address)) :\n\(page.content.prefix(8000))"
            } catch {
                let text = describe(error)
                finishStep(stepID, detail: host, error: text, in: conversationID, messageID: messageID)
                return "Impossible de lire la page : \(text)"
            }
        default:
            return "Outil inconnu : \(call.function.name)."
        }
    }

    /// Numérote les résultats comme les sources affichées ([1], [2]…), sans doublon d’adresse.
    func registerWebSources(_ results: [WebResult], in conversationID: UUID, messageID: UUID) -> [(tag: String, result: WebResult)] {
        var tagged: [(tag: String, result: WebResult)] = []
        updateMessage(messageID, in: conversationID) { message in
            for result in results {
                if let existing = message.sources.first(where: { $0.url == result.url }) {
                    tagged.append((existing.tag, result))
                    continue
                }
                let number = message.sources.filter { $0.url != nil }.count + 1
                let source = Source(tag: "\(number)", title: result.title, url: result.url, detail: URL(string: result.url)?.host())
                message.sources.append(source)
                tagged.append((source.tag, result))
            }
        }
        return tagged
    }

    func addStep(_ kind: ToolStep.Kind, detail: String, in conversationID: UUID, messageID: UUID) -> UUID {
        let step = ToolStep(kind: kind, detail: detail, isRunning: true)
        updateMessage(messageID, in: conversationID) { $0.steps.append(step) }
        return step.id
    }

    func finishStep(_ id: UUID, detail: String, count: Int? = nil, error: String? = nil, in conversationID: UUID, messageID: UUID) {
        updateMessage(messageID, in: conversationID) { message in
            guard let index = message.steps.firstIndex(where: { $0.id == id }) else { return }
            message.steps[index].isRunning = false
            message.steps[index].detail = detail
            message.steps[index].resultCount = count
            message.steps[index].error = error
        }
    }

    /// Passages des documents pour la question (vecteurs si disponibles, sinon mots-clés).
    func documentExcerpts(for question: String, documents: [DocumentRef]) async -> [DocumentExcerpt] {
        var indexes: [UUID: DocumentIndex] = [:]
        for document in documents {
            if let index = AttachmentStore.shared.loadIndex(for: document.id) { indexes[document.id] = index }
        }
        var questionVectors: [String: [Float]] = [:]
        let installed = Set(models.map(\.name))
        let neededModels = Set(indexes.values.compactMap(\.embeddingModel)).filter { installed.contains($0) }
        if let client = try? makeClient() {
            for model in neededModels {
                if let vector = try? await client.embed(model: model, inputs: [question]).first {
                    questionVectors[model] = vector
                }
            }
        }
        return DocumentService.excerpts(for: question, documents: documents, indexes: indexes, questionVector: questionVectors)
    }
}
