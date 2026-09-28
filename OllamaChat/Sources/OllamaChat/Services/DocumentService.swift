import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Passage d’un document, avec sa page quand elle est connue (PDF).
struct DocumentChunk: Codable, Equatable {
    var text: String
    var page: Int?
}

/// Contenu indexé d’un document joint.
struct DocumentIndex: Codable, Equatable {
    var chunks: [DocumentChunk]
    /// Vecteurs des passages (même ordre que `chunks`), si un modèle d’indexation était disponible.
    var vectors: [[Float]]?
    var embeddingModel: String?

    var characterCount: Int { chunks.reduce(0) { $0 + $1.text.count } }
}

/// Extrait retenu pour répondre à une question.
struct DocumentExcerpt: Equatable {
    var tag: String
    var documentName: String
    var page: Int?
    var text: String
    var isFullText: Bool
}

enum DocumentError: LocalizedError {
    case unsupported(String)
    case unreadable(String)
    case empty(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let name): return "Format non pris en charge : « \(name) »."
        case .unreadable(let name): return "Impossible de lire « \(name) »."
        case .empty(let name): return "« \(name) » ne contient pas de texte exploitable (document scanné ?)."
        }
    }
}

enum DocumentService {
    /// En dessous de cette taille (en caractères, tous documents confondus), le texte entier est donné au modèle.
    static let fullTextLimit = 12_000
    static let chunkSize = 1_200
    static let chunkOverlap = 200
    static let topK = 6

    // MARK: - Formats

    static let wordType = UTType("org.openxmlformats.wordprocessingml.document")
    static let markdownType = UTType(filenameExtension: "md")

    static var supportedTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .text, .utf8PlainText, .rtf, .rtfd, .html, .commaSeparatedText, .json, .sourceCode, .xml]
        if let wordType { types.append(wordType) }
        if let markdownType { types.append(markdownType) }
        return types
    }

    static func isDocument(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Extraction

    /// Texte du document, page par page pour un PDF.
    static func extractPages(from url: URL) throws -> [String] {
        let name = url.lastPathComponent
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            throw DocumentError.unsupported(name)
        }
        var pages: [String]
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(url: url) else { throw DocumentError.unreadable(name) }
            pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        } else if type.conforms(to: .html) {
            // NSAttributedString passe par WebKit pour le HTML (fil principal obligatoire) : extraction maison.
            guard let data = try? Data(contentsOf: url) else { throw DocumentError.unreadable(name) }
            pages = [HTMLText.extract(String(decoding: data, as: UTF8.self)).text]
        } else if type.conforms(to: .rtf) || type.conforms(to: .rtfd) || (wordType.map { type.conforms(to: $0) } ?? false) {
            guard let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else {
                throw DocumentError.unreadable(name)
            }
            pages = [attributed.string]
        } else if type.conforms(to: .text) || type.conforms(to: .json) || type.conforms(to: .sourceCode) || type.conforms(to: .xml) {
            guard let data = try? Data(contentsOf: url) else { throw DocumentError.unreadable(name) }
            pages = [String(decoding: data, as: UTF8.self)]
        } else {
            throw DocumentError.unsupported(name)
        }
        pages = pages.map { $0.replacingOccurrences(of: "\r\n", with: "\n") }
        guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw DocumentError.empty(name)
        }
        return pages
    }

    /// Découpe en passages d’environ `chunkSize` caractères, en coupant de préférence entre deux paragraphes.
    static func chunk(pages: [String], size: Int = chunkSize, overlap: Int = chunkOverlap) -> [DocumentChunk] {
        var chunks: [DocumentChunk] = []
        let isPaged = pages.count > 1
        for (pageIndex, page) in pages.enumerated() {
            let text = page.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let pageNumber = isPaged ? pageIndex + 1 : nil
            var start = text.startIndex
            while start < text.endIndex {
                var end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
                if end < text.endIndex {
                    // Recule jusqu’à une fin de paragraphe ou de phrase, si elle n’est pas trop loin.
                    let window = text[start..<end]
                    let minimum = text.index(start, offsetBy: size / 2)
                    if let cut = window.range(of: "\n\n", options: .backwards), cut.lowerBound > minimum {
                        end = cut.upperBound
                    } else if let cut = window.range(of: ". ", options: .backwards), cut.lowerBound > minimum {
                        end = cut.upperBound
                    }
                }
                let piece = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { chunks.append(DocumentChunk(text: piece, page: pageNumber)) }
                guard end < text.endIndex else { break }
                let next = text.index(end, offsetBy: -overlap, limitedBy: start) ?? start
                start = next > start ? next : end
            }
        }
        return chunks
    }

    /// Lit, découpe et, si possible, vectorise un document.
    static func buildIndex(from url: URL, client: OllamaClient?, embeddingModel: String?) async throws -> (index: DocumentIndex, pageCount: Int?) {
        let pages = try extractPages(from: url)
        let chunks = chunk(pages: pages)
        var index = DocumentIndex(chunks: chunks, vectors: nil, embeddingModel: nil)
        // Tous les documents sont vectorisés, même courts : joints à d’autres, ils se classent de la même façon.
        if let client, let embeddingModel, !embeddingModel.isEmpty {
            do {
                var vectors: [[Float]] = []
                for batchStart in stride(from: 0, to: chunks.count, by: 16) {
                    let batch = chunks[batchStart..<min(batchStart + 16, chunks.count)].map(\.text)
                    vectors.append(contentsOf: try await client.embed(model: embeddingModel, inputs: batch))
                }
                if vectors.count == chunks.count {
                    index.vectors = vectors
                    index.embeddingModel = embeddingModel
                }
            } catch {
                // Sans vecteurs, la recherche se fait par mots-clés : le document reste utilisable.
                if Task.isCancelled { throw error }
                NSLog("OllamaChat : vectorisation impossible avec \(embeddingModel) : \(error)")
            }
        }
        return (index, pages.count > 1 ? pages.count : nil)
    }

    // MARK: - Recherche des passages

    /// Passages les plus utiles pour la question, ou texte entier des documents courts.
    static func excerpts(
        for question: String,
        documents: [DocumentRef],
        indexes: [UUID: DocumentIndex],
        questionVector: [String: [Float]]
    ) -> [DocumentExcerpt] {
        let available = documents.compactMap { document in indexes[document.id].map { (document, $0) } }
        let totalCharacters = available.reduce(0) { $0 + $1.1.characterCount }
        var excerpts: [DocumentExcerpt] = []

        if totalCharacters <= fullTextLimit {
            for (document, index) in available {
                let text = index.chunks.map(\.text).joined(separator: "\n\n")
                excerpts.append(DocumentExcerpt(tag: "", documentName: document.name, page: nil, text: text, isFullText: true))
            }
        } else {
            // Tous les passages de tous les documents sont classés ensemble, avec une même mesure.
            var candidates: [(document: DocumentRef, chunk: DocumentChunk, vector: [Float]?)] = []
            for (document, index) in available {
                let vectors = index.vectors?.count == index.chunks.count ? index.vectors : nil
                for (position, chunk) in index.chunks.enumerated() {
                    candidates.append((document, chunk, vectors?[position]))
                }
            }
            let keyword = bm25Scores(query: question, chunks: candidates.map { $0.chunk }).map { $0.1 }
            let bestKeyword = keyword.max() ?? 0
            // Par le sens si tous les passages ont été vectorisés par le même modèle, complété par
            // les mots-clés (noms propres, nombres) ; sinon par les mots-clés seuls.
            var query: [Float]?
            let models = Set(available.map { $0.1.embeddingModel })
            if models.count == 1, let model = models.first ?? nil, candidates.allSatisfy({ $0.vector != nil }) {
                query = questionVector[model]
            }
            let scores = candidates.indices.map { position -> Double in
                let keywordScore = bestKeyword > 0 ? keyword[position] / bestKeyword : 0
                guard let query, let vector = candidates[position].vector else { return keywordScore }
                return 0.7 * Double(cosine(vector, query)) + 0.3 * keywordScore
            }
            for position in candidates.indices.sorted(by: { scores[$0] > scores[$1] }).prefix(topK) {
                let item = candidates[position]
                excerpts.append(DocumentExcerpt(tag: "", documentName: item.document.name, page: item.chunk.page, text: item.chunk.text, isFullText: false))
            }
        }
        for position in excerpts.indices {
            excerpts[position].tag = "D\(position + 1)"
        }
        return excerpts
    }

    static func format(_ excerpts: [DocumentExcerpt]) -> String {
        var text = "Extraits des documents joints :\n"
        for excerpt in excerpts {
            var label = "« \(excerpt.documentName) »"
            if excerpt.isFullText {
                label += " (texte intégral)"
            } else if let page = excerpt.page {
                label += ", page \(page)"
            }
            text += "\n[\(excerpt.tag)] \(label)\n\(excerpt.text)\n"
        }
        return text
    }

    /// Place réservée aux extraits dans l’estimation du contexte.
    static func excerptBudgetTokens(for documents: [DocumentRef]) -> Int {
        let characters = documents.filter { $0.status == .ready }.reduce(0) { $0 + $1.characterCount }
        guard characters > 0 else { return 0 }
        return TokenEstimator.tokens(forCharacterCount: min(characters, max(fullTextLimit, topK * chunkSize)))
    }

    // MARK: - Classement

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// Score BM25 de chaque passage pour la question (recherche par mots-clés).
    static func bm25Scores(query: String, chunks: [DocumentChunk], k1: Double = 1.4, b: Double = 0.75) -> [(Int, Double)] {
        let queryTerms = Set(terms(query))
        guard !queryTerms.isEmpty, !chunks.isEmpty else { return chunks.indices.map { ($0, 0) } }
        let documents = chunks.map { terms($0.text) }
        let averageLength = Double(documents.reduce(0) { $0 + $1.count }) / Double(documents.count)
        var documentFrequency: [String: Int] = [:]
        for words in documents {
            for term in Set(words) where queryTerms.contains(term) {
                documentFrequency[term, default: 0] += 1
            }
        }
        let count = Double(documents.count)
        return documents.enumerated().map { position, words in
            var frequencies: [String: Int] = [:]
            for word in words where queryTerms.contains(word) { frequencies[word, default: 0] += 1 }
            var score = 0.0
            for (term, frequency) in frequencies {
                let df = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (count - df + 0.5) / (df + 0.5))
                let tf = Double(frequency)
                score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * Double(words.count) / max(averageLength, 1)))
            }
            return (position, score)
        }
    }

    /// Mots en minuscules, sans accents ni mots vides.
    static func terms(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !MemoryText.stopWords.contains($0) && !questionWords.contains($0) }
    }

    private static let questionWords: Set<String> = [
        "quel", "quelle", "quels", "quelles", "comment", "pourquoi", "quand", "combien", "est", "what", "which", "how", "why", "when",
        "le", "la", "un", "de", "et", "en", "au", "il", "je", "tu", "ce", "ou", "si", "ne", "me", "te", "se",
    ]
}
