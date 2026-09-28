import Foundation
import Observation

/// Un souvenir sur l’utilisateur, réutilisé d’une conversation à l’autre.
struct Memory: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    var conversationID: UUID?
}

/// Souvenirs enregistrés dans « Application Support/OllamaChat/memories.json ».
/// Tout reste sur le Mac ; la liste est visible et modifiable dans les réglages.
@MainActor
@Observable
final class MemoryStore {
    private(set) var memories: [Memory] = []
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? AppPaths.support.appending(path: "memories.json", directoryHint: .notDirectory)
        if let data = try? Data(contentsOf: self.url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            memories = (try? decoder.decode([Memory].self, from: data)) ?? []
        }
    }

    /// Ajoute un souvenir s’il n’est pas déjà connu. Renvoie `true` s’il a été ajouté.
    @discardableResult
    func add(_ rawText: String, conversationID: UUID? = nil) -> Bool {
        let text = MemoryText.clean(rawText)
        guard text.count >= 4, !MemoryText.isDuplicate(text, of: memories.map(\.text)) else { return false }
        memories.append(Memory(text: text, conversationID: conversationID))
        save()
        return true
    }

    func update(_ id: UUID, text: String) {
        let cleaned = MemoryText.clean(text)
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        if cleaned.isEmpty {
            memories.remove(at: index)
        } else {
            memories[index].text = cleaned
        }
        save()
    }

    func remove(_ id: UUID) {
        memories.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        memories.removeAll()
        save()
    }

    /// Oublie les souvenirs qui correspondent à la phrase. Renvoie le nombre de souvenirs retirés.
    @discardableResult
    func forget(matching phrase: String) -> Int {
        let before = memories.count
        memories.removeAll { MemoryText.matches($0.text, phrase: phrase) }
        let removed = before - memories.count
        if removed > 0 { save() }
        return removed
    }

    /// Textes à donner au modèle : les plus récents d’abord, dans la limite d’environ 3 000 caractères.
    func textsForPrompt(limit: Int = 3000) -> [String] {
        var result: [String] = []
        var total = 0
        for memory in memories.reversed() {
            total += memory.text.count
            if total > limit { break }
            result.append(memory.text)
        }
        return result.reversed()
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            try encoder.encode(memories).write(to: url, options: .atomic)
        } catch {
            NSLog("OllamaChat : échec de l’enregistrement de la mémoire : \(error)")
        }
    }
}

/// Commande de mémoire tapée par l’utilisateur au début d’un message.
enum MemoryCommand: Equatable {
    case remember(String)
    case forget(String)

    private static let rememberPrefixes = [
        "retiens que", "retiens bien que", "souviens-toi que", "souviens toi que", "rappelle-toi que",
        "rappelle toi que", "n’oublie pas que", "n'oublie pas que", "mémorise que", "note que",
        "retiens :", "retiens:", "retiens",
    ]
    private static let forgetPrefixes = [
        "oublie que", "oublie :", "oublie:", "efface de ta mémoire", "ne retiens plus que", "oublie",
    ]

    static func parse(_ text: String) -> MemoryCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for prefix in forgetPrefixes where hasCommandPrefix(lower, prefix) {
            let rest = remainder(of: trimmed, afterPrefixLength: prefix.count)
            return rest.isEmpty ? nil : .forget(rest)
        }
        for prefix in rememberPrefixes where hasCommandPrefix(lower, prefix) {
            let rest = remainder(of: trimmed, afterPrefixLength: prefix.count)
            return rest.count < 3 ? nil : .remember(rest)
        }
        return nil
    }

    /// Le préfixe doit être un mot entier : « oublie » ne doit pas reconnaître « oublier ».
    private static func hasCommandPrefix(_ text: String, _ prefix: String) -> Bool {
        guard text.hasPrefix(prefix) else { return false }
        if prefix.hasSuffix(":") { return true }
        guard let next = text.dropFirst(prefix.count).first else { return true }
        return next.isWhitespace || next == ":" || next == ","
    }

    private static func remainder(of text: String, afterPrefixLength length: Int) -> String {
        String(text.dropFirst(length))
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,")))
    }
}

/// Outils de comparaison et de mise en forme des souvenirs.
enum MemoryText {
    static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        guard let first = result.first else { return "" }
        result = first.uppercased() + result.dropFirst()
        if let last = result.last, !".!?…".contains(last) { result += "." }
        return String(result.prefix(300))
    }

    /// Souvenir tel qu’il est donné au modèle : une phrase à la première personne (« Retiens que je… »)
    /// est rapportée comme une parole de l’utilisateur, pour que le modèle ne se l’attribue pas.
    static func forPrompt(_ text: String) -> String {
        let firstWord = text.prefix { $0.isLetter }.lowercased()
        let firstPerson: Set<String> = ["je", "j", "moi", "mon", "ma", "mes", "nous", "notre", "nos", "on", "i", "my", "we", "our"]
        return firstPerson.contains(firstWord) ? "L’utilisateur a dit : « \(text) »" : text
    }

    /// Mots significatifs, en minuscules et sans accents.
    static func words(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { $0.count > 2 && !stopWords.contains($0) })
    }

    static func isDuplicate(_ text: String, of existing: [String]) -> Bool {
        let candidate = words(text)
        guard !candidate.isEmpty else { return true }
        return existing.contains { other in
            let otherWords = words(other)
            guard !otherWords.isEmpty else { return false }
            let overlap = Double(candidate.intersection(otherWords).count)
            return overlap / Double(candidate.union(otherWords).count) >= 0.75
        }
    }

    /// Le souvenir contient-il l’essentiel des mots de la phrase ?
    static func matches(_ memory: String, phrase: String) -> Bool {
        let wanted = words(phrase)
        guard !wanted.isEmpty else { return false }
        let present = wanted.intersection(words(memory)).count
        return Double(present) / Double(wanted.count) >= 0.6
    }

    static let stopWords: Set<String> = [
        "les", "des", "une", "que", "qui", "est", "sont", "pour", "dans", "avec", "sur", "par", "pas", "plus",
        "mon", "ton", "son", "mes", "tes", "ses", "nos", "vos", "leur", "leurs", "cette", "ces", "aux", "du",
        "utilisateur", "l'utilisateur", "moi", "toi", "lui", "elle", "nous", "vous", "ils", "elles", "suis",
        "the", "and", "for", "with", "that", "this", "user", "has", "have", "are", "was",
    ]
}
