import XCTest
@testable import OllamaChat

final class MemoryTests: XCTestCase {
    func testRememberCommands() {
        XCTAssertEqual(MemoryCommand.parse("Retiens que je m’appelle Anka"), .remember("je m’appelle Anka"))
        XCTAssertEqual(MemoryCommand.parse("souviens-toi que j'ai un Mac mini M4."), .remember("j'ai un Mac mini M4."))
        XCTAssertEqual(MemoryCommand.parse("Retiens : je code en Swift"), .remember("je code en Swift"))
        XCTAssertNil(MemoryCommand.parse("Retiens"))
    }

    func testForgetCommands() {
        XCTAssertEqual(MemoryCommand.parse("Oublie que j'habite à Lyon"), .forget("j'habite à Lyon"))
        XCTAssertEqual(MemoryCommand.parse("oublie mon adresse"), .forget("mon adresse"))
        // « oublier » n’est pas la commande « oublie ».
        XCTAssertNil(MemoryCommand.parse("Oublier le passé, c’est difficile"))
        XCTAssertNil(MemoryCommand.parse("Quel temps fait-il ?"))
    }

    func testCleanAndDuplicates() {
        XCTAssertEqual(MemoryText.clean("  l'utilisateur aime le café  "), "L'utilisateur aime le café.")
        XCTAssertEqual(MemoryText.clean("Il vit à Lyon !"), "Il vit à Lyon !")
        XCTAssertTrue(MemoryText.isDuplicate("L’utilisateur vit à Lyon.", of: ["L'utilisateur vit à Lyon"]))
        XCTAssertFalse(MemoryText.isDuplicate("L’utilisateur vit à Paris.", of: ["L'utilisateur possède un chat."]))
        XCTAssertTrue(MemoryText.matches("L'utilisateur habite à Lyon.", phrase: "j'habite à Lyon"))
        XCTAssertFalse(MemoryText.matches("L'utilisateur a un chat.", phrase: "j'habite à Lyon"))
    }

    @MainActor
    func testMemoryStore() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "memories-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MemoryStore(url: url)
        XCTAssertTrue(store.add("L'utilisateur s'appelle Anka"))
        XCTAssertFalse(store.add("l’utilisateur s’appelle Anka."), "doublon")
        XCTAssertTrue(store.add("L'utilisateur a un Mac mini M4"))
        XCTAssertEqual(store.memories.count, 2)
        XCTAssertEqual(MemoryStore(url: url).memories.count, 2, "enregistré sur le disque")
        XCTAssertEqual(store.forget(matching: "Mac mini M4"), 1)
        XCTAssertEqual(store.textsForPrompt(), ["L'utilisateur s'appelle Anka."])
    }

    func testFirstPersonMemoriesAreQuoted() {
        XCTAssertEqual(MemoryText.forPrompt("Je travaille de nuit."), "L’utilisateur a dit : « Je travaille de nuit. »")
        XCTAssertEqual(MemoryText.forPrompt("J’ai un Mac mini M4."), "L’utilisateur a dit : « J’ai un Mac mini M4. »")
        XCTAssertEqual(MemoryText.forPrompt("L'utilisateur a un chat."), "L'utilisateur a un chat.")
        XCTAssertEqual(MemoryText.forPrompt("Jean est son frère."), "Jean est son frère.")
    }

    func testExtractionParsing() {
        XCTAssertEqual(
            MemoryExtraction.parse(#"{"souvenirs": ["L'utilisateur est infirmier.", "court"]}"#),
            ["L'utilisateur est infirmier."]
        )
        XCTAssertEqual(MemoryExtraction.parse("<think>hmm</think>\n{\"souvenirs\": []}"), [])
        XCTAssertEqual(MemoryExtraction.parse("pas de JSON"), [])
    }
}

final class TitleTests: XCTestCase {
    func testTitleCleaning() {
        XCTAssertEqual(TitleCleaner.clean("« Recette de crêpes »"), "Recette de crêpes")
        XCTAssertEqual(TitleCleaner.clean("Titre : Voyage au Japon.\nAutre ligne"), "Voyage au Japon")
        XCTAssertEqual(TitleCleaner.clean("<think>réflexion</think>Installer Ollama"), "Installer Ollama")
        XCTAssertNil(TitleCleaner.clean("  "))
    }
}

final class PromptTests: XCTestCase {
    func testNoSystemPromptByDefault() {
        XCTAssertNil(PromptBuilder.systemPrompt(PromptContext(profile: .balanced)))
    }

    func testSystemPromptSections() throws {
        var context = PromptContext(profile: .rigorous)
        context.aboutMe = "Je m'appelle Anka."
        context.memories = ["L'utilisateur a un Mac mini M4."]
        context.webSearch = .tools
        context.documentNames = ["rapport.pdf"]
        let prompt = try XCTUnwrap(PromptBuilder.systemPrompt(context))
        XCTAssertTrue(prompt.hasPrefix("Date du jour :"))
        XCTAssertTrue(prompt.contains("Distingue clairement les faits"))
        XCTAssertTrue(prompt.contains("Je m'appelle Anka."))
        XCTAssertTrue(prompt.contains("- L'utilisateur a un Mac mini M4."))
        XCTAssertTrue(prompt.contains("web_search"))
        XCTAssertTrue(prompt.contains("« rapport.pdf »"))
    }

    func testTokenEstimate() {
        XCTAssertEqual(TokenEstimator.tokens(in: ""), 0)
        XCTAssertEqual(TokenEstimator.tokens(in: String(repeating: "a", count: 350)), 100)
    }

    func testProfiles() {
        XCTAssertEqual(ResponseProfile.profile(id: "code"), .code)
        XCTAssertEqual(ResponseProfile.profile(id: "inconnu"), .balanced)
        XCTAssertEqual(ResponseProfile.rigorous.temperature, 0.3)
    }
}

final class DocumentTests: XCTestCase {
    func testChunkingKeepsEverythingWithOverlap() {
        let paragraph = String(repeating: "Phrase de test numéro un. ", count: 20)
        let text = (1...10).map { "Paragraphe \($0). " + paragraph }.joined(separator: "\n\n")
        let chunks = DocumentService.chunk(pages: [text], size: 1200, overlap: 200)
        XCTAssertGreaterThan(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 1200 && $0.page == nil })
        XCTAssertTrue(chunks.first?.text.hasPrefix("Paragraphe 1.") ?? false)
        XCTAssertTrue(chunks.last?.text.hasSuffix("numéro un.") ?? false)
    }

    func testPagesAreNumbered() {
        let chunks = DocumentService.chunk(pages: ["Première page.", "", "Troisième page."])
        XCTAssertEqual(chunks.map(\.page), [1, 3])
    }

    func testKeywordRankingFindsTheRightPassage() {
        let chunks = [
            DocumentChunk(text: "La recette des crêpes demande de la farine, des œufs et du lait.", page: 1),
            DocumentChunk(text: "Le code secret du projet Hibiscus est 4721.", page: 2),
            DocumentChunk(text: "Les réunions ont lieu le mardi matin dans la salle bleue.", page: 3),
        ]
        let scores = DocumentService.bm25Scores(query: "Quel est le code secret du projet Hibiscus ?", chunks: chunks)
        let best = scores.max { $0.1 < $1.1 }
        XCTAssertEqual(best?.0, 1)
    }

    func testCosine() {
        XCTAssertEqual(DocumentService.cosine([1, 0], [1, 0]), 1, accuracy: 0.0001)
        XCTAssertEqual(DocumentService.cosine([1, 0], [0, 1]), 0, accuracy: 0.0001)
        XCTAssertEqual(DocumentService.cosine([1, 2], [1]), 0)
    }

    func testShortDocumentsAreGivenInFull() {
        let document = DocumentRef(name: "notes.txt", characterCount: 40, chunkCount: 1, status: .ready)
        let index = DocumentIndex(chunks: [DocumentChunk(text: "Le code secret est 4721.", page: nil)])
        let excerpts = DocumentService.excerpts(for: "code ?", documents: [document], indexes: [document.id: index], questionVector: [:])
        XCTAssertEqual(excerpts.count, 1)
        XCTAssertEqual(excerpts.first?.tag, "D1")
        XCTAssertTrue(excerpts.first?.isFullText ?? false)
        XCTAssertTrue(DocumentService.format(excerpts).contains("[D1] « notes.txt » (texte intégral)"))
    }

    func testLongDocumentsUseRetrieval() {
        let filler = String(repeating: "Texte sans rapport avec la question posée. ", count: 30)
        var chunks = (0..<20).map { DocumentChunk(text: filler + "\($0)", page: $0 + 1) }
        chunks[13] = DocumentChunk(text: "Le budget du projet Hibiscus est de 12 000 euros.", page: 14)
        let document = DocumentRef(name: "rapport.pdf", status: .ready)
        let index = DocumentIndex(chunks: chunks)
        let excerpts = DocumentService.excerpts(for: "budget du projet Hibiscus", documents: [document], indexes: [document.id: index], questionVector: [:])
        XCTAssertEqual(excerpts.count, DocumentService.topK)
        XCTAssertEqual(excerpts.first?.page, 14)
        XCTAssertFalse(excerpts.first?.isFullText ?? true)
    }

    func testVectorsRankByMeaningAcrossDocuments() {
        let filler = String(repeating: "Texte sans rapport avec la question posée. ", count: 30)
        var chunks = (0..<12).map { DocumentChunk(text: filler + "\($0)", page: $0 + 1) }
        chunks[4] = DocumentChunk(text: "Les dépenses prévues pour l’initiative atteignent douze mille euros.", page: 5)
        var vectors = [[Float]](repeating: [0, 1], count: 12)
        vectors[4] = [1, 0]
        let long = DocumentRef(name: "rapport.pdf", status: .ready)
        let short = DocumentRef(name: "notes.txt", status: .ready)
        let indexes = [
            long.id: DocumentIndex(chunks: chunks, vectors: vectors, embeddingModel: "m"),
            short.id: DocumentIndex(chunks: [DocumentChunk(text: "Le chat dort sur le canapé.", page: nil)], vectors: [[0, 1]], embeddingModel: "m"),
        ]
        let excerpts = DocumentService.excerpts(for: "Quel est le budget ?", documents: [long, short], indexes: indexes, questionVector: ["m": [1, 0]])
        XCTAssertEqual(excerpts.first?.page, 5, "le passage le plus proche par le sens, sans mot commun")
        XCTAssertEqual(excerpts.first?.documentName, "rapport.pdf")
    }

    func testMixedIndexesFallBackToKeywords() {
        let filler = String(repeating: "Texte sans rapport avec la question posée. ", count: 30)
        let chunks = (0..<12).map { DocumentChunk(text: filler + "\($0)", page: $0 + 1) }
        let withVectors = DocumentRef(name: "rapport.pdf", status: .ready)
        let withoutVectors = DocumentRef(name: "notes.txt", status: .ready)
        let indexes = [
            withVectors.id: DocumentIndex(chunks: chunks, vectors: [[Float]](repeating: [1, 0], count: 12), embeddingModel: "m"),
            withoutVectors.id: DocumentIndex(chunks: [DocumentChunk(text: "Le budget du projet Hibiscus est de 12 000 euros.", page: nil)]),
        ]
        let excerpts = DocumentService.excerpts(for: "budget du projet Hibiscus", documents: [withVectors, withoutVectors], indexes: indexes, questionVector: ["m": [1, 0]])
        XCTAssertEqual(excerpts.first?.documentName, "notes.txt", "mêmes règles pour tous : les mots-clés")
    }

    func testExtractPlainText() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "doc-\(UUID().uuidString).txt")
        try "Bonjour\r\nle monde".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try DocumentService.extractPages(from: url), ["Bonjour\nle monde"])
        XCTAssertTrue(DocumentService.isDocument(url))
        XCTAssertFalse(DocumentService.isDocument(URL(fileURLWithPath: "/tmp/photo.jpg")))
    }
}

final class WebTests: XCTestCase {
    func testHTMLExtraction() {
        let html = """
        <html><head><title>Titre &amp; test</title><style>p{}</style></head>
        <body><nav>menu</nav><script>alert(1)</script><h1>Bonjour</h1><p>Il fait &#233;t&eacute;&nbsp;!</p></body></html>
        """
        let page = HTMLText.extract(html)
        XCTAssertEqual(page.title, "Titre & test")
        XCTAssertEqual(page.text, "Bonjour\nIl fait été !")
    }

    func testFormattedResults() {
        let text = WebSearchService.formatResults([("1", WebResult(title: "Ollama", url: "https://ollama.com", content: "Modèles locaux"))], query: "ollama")
        XCTAssertTrue(text.contains("[1] Ollama\nhttps://ollama.com\nModèles locaux"))
        XCTAssertEqual(WebSearchService.formatResults([], query: "x"), "Aucun résultat pour « x ».")
    }

    func testToolCallDecoding() throws {
        let line = #"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"web_search","arguments":{"query":"météo Lyon"}}}]},"done":true}"#
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(line.utf8))
        XCTAssertEqual(chunk.message?.toolCalls?.first?.function.name, "web_search")
        XCTAssertEqual(chunk.message?.toolCalls?.first?.function.arguments["query"]?.stringValue, "météo Lyon")
    }

    func testToolDefinitionsEncoding() throws {
        let data = try JSONEncoder().encode(WebSearchService.tools)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains(#""name":"web_search""#))
        XCTAssertTrue(json.contains(#""type":"function""#))
    }
}

final class ModelTests: XCTestCase {
    func testGuessedCapabilities() {
        XCTAssertTrue(ModelInfo.guessed(for: "qwen3:8b").supportsThinking)
        XCTAssertTrue(ModelInfo.guessed(for: "gemma3:4b").supportsVision)
        XCTAssertTrue(ModelInfo.guessed(for: "embeddinggemma:latest").isEmbeddingModel)
        XCTAssertTrue(ModelInfo.guessed(for: "gpt-oss:20b").usesThinkingLevels)
        XCTAssertFalse(ModelInfo.guessed(for: "llama3.2").supportsThinking)
    }

    func testLegacyConversationDecoding() throws {
        let json = """
        [{"id":"11111111-2222-3333-4444-555555555555","title":"Ancienne","model":"llama3.2",
          "createdAt":"2026-01-01T10:00:00Z","updatedAt":"2026-01-01T10:00:00Z",
          "messages":[{"id":"AAAAAAAA-0000-0000-0000-000000000001","role":"user","content":"Bonjour","thinking":"","createdAt":"2026-01-01T10:00:00Z"}]}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conversation = try XCTUnwrap(decoder.decode([Conversation].self, from: Data(json.utf8)).first)
        XCTAssertEqual(conversation.profileID, ResponseProfile.balanced.id)
        XCTAssertEqual(conversation.thinking, .on)
        XCTAssertTrue(conversation.titleGenerated, "les anciennes conversations gardent leur titre")
        XCTAssertEqual(conversation.memoryProcessedCount, 1, "elles ne sont pas relues pour la mémoire")
        XCTAssertEqual(conversation.messages.first?.kind, .normal)
        XCTAssertEqual(conversation.messages.first?.images, [])
    }

    func testThinkEncoding() throws {
        XCTAssertEqual(String(data: try JSONEncoder().encode(OllamaClient.Think.enabled(false)), encoding: .utf8), "false")
        XCTAssertEqual(String(data: try JSONEncoder().encode(OllamaClient.Think.level("high")), encoding: .utf8), "\"high\"")
    }
}

final class ExportTests: XCTestCase {
    func testMarkdownExport() {
        var conversation = Conversation(title: "Question / réponse", model: "qwen3")
        conversation.messages = [
            ChatMessage(role: .user, content: "Quelle est la capitale de la France ?"),
            {
                var message = ChatMessage(role: .assistant, content: "Paris [1].", model: "qwen3")
                message.thinking = "La capitale…"
                message.sources = [Source(tag: "1", title: "Wikipédia", url: "https://fr.wikipedia.org/wiki/Paris", detail: nil)]
                return message
            }(),
        ]
        let markdown = ConversationExporter.markdown(for: conversation)
        XCTAssertTrue(markdown.hasPrefix("# Question / réponse"))
        XCTAssertTrue(markdown.contains("## Vous\n\nQuelle est la capitale de la France ?"))
        XCTAssertTrue(markdown.contains("## Assistant (qwen3)"))
        XCTAssertTrue(markdown.contains("> La capitale…"))
        XCTAssertTrue(markdown.contains("- [1] [Wikipédia](https://fr.wikipedia.org/wiki/Paris)"))
        XCTAssertEqual(ConversationExporter.fileName(for: conversation), "Question - réponse.md")
    }
}
