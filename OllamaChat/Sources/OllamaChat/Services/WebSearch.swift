import Foundation
import Security

enum WebSearchProvider: String, CaseIterable, Identifiable {
    /// API de recherche d’Ollama : compte gratuit et clé API sur ollama.com.
    case ollama
    /// Moteur SearXNG auto-hébergé (format JSON activé).
    case searxng

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ollama: return "Ollama (compte gratuit)"
        case .searxng: return "SearXNG (auto-hébergé)"
        }
    }
}

struct WebResult: Equatable {
    var title: String
    var url: String
    var content: String
}

struct WebPage: Equatable {
    var title: String
    var content: String
}

enum WebSearchError: LocalizedError {
    case missingAPIKey
    case missingServer
    case http(status: Int, message: String?)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Recherche web non configurée : ajoutez votre clé API Ollama dans Réglages › Recherche web."
        case .missingServer:
            return "Recherche web non configurée : indiquez l’adresse de votre serveur SearXNG dans Réglages › Recherche web."
        case .http(let status, let message):
            if status == 401 || status == 403 { return "Clé API refusée par le service de recherche (code \(status))." }
            return message.map { "Recherche web impossible : \($0)" } ?? "Recherche web impossible (code HTTP \(status))."
        case .invalidURL(let url):
            return "Adresse invalide : \(url)"
        }
    }
}

/// Recherche et lecture de pages web pour le modèle.
struct WebSearchService {
    var provider: WebSearchProvider
    var apiKey: String?
    var ollamaBaseURL: URL
    var searxngURL: URL?

    static let keychainAccount = "ollama-web-search-api-key"
    /// Nombre maximal d’allers-retours avec les outils avant d’exiger une réponse.
    static let maxRounds = 4

    /// Service configuré d’après les réglages.
    static func current() -> WebSearchService {
        let defaults = UserDefaults.standard
        let provider = WebSearchProvider(rawValue: defaults.string(forKey: SettingsKey.webSearchProvider) ?? "") ?? .ollama
        let base = URL(string: defaults.string(forKey: SettingsKey.ollamaWebSearchURL) ?? "") ?? URL(string: AppDefaults.ollamaWebSearchURL)!
        let searxng = (defaults.string(forKey: SettingsKey.searxngURL) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return WebSearchService(
            provider: provider,
            apiKey: Keychain.read(account: keychainAccount),
            ollamaBaseURL: base,
            searxngURL: searxng.isEmpty ? nil : URL(string: searxng.contains("://") ? searxng : "http://" + searxng)
        )
    }

    var isConfigured: Bool {
        switch provider {
        case .ollama: return !(apiKey ?? "").isEmpty
        case .searxng: return searxngURL != nil
        }
    }

    static let tools: [OllamaClient.Tool] = [
        OllamaClient.Tool(
            name: "web_search",
            description: "Cherche sur Internet et renvoie les résultats les plus pertinents (titre, adresse, extrait). À utiliser pour les informations récentes ou précises.",
            parameters: [
                "type": "object",
                "properties": ["query": ["type": "string", "description": "La requête de recherche"]],
                "required": ["query"],
            ]
        ),
        OllamaClient.Tool(
            name: "web_fetch",
            description: "Lit le contenu textuel d’une page web à partir de son adresse.",
            parameters: [
                "type": "object",
                "properties": ["url": ["type": "string", "description": "L’adresse complète de la page"]],
                "required": ["url"],
            ]
        ),
    ]

    func search(_ query: String, maxResults: Int = 5) async throws -> [WebResult] {
        switch provider {
        case .ollama:
            guard let apiKey, !apiKey.isEmpty else { throw WebSearchError.missingAPIKey }
            struct Body: Encodable {
                let query: String
                let max_results: Int
            }
            struct Response: Decodable {
                struct Result: Decodable {
                    let title: String?
                    let url: String?
                    let content: String?
                }
                let results: [Result]?
            }
            let data = try await post(ollamaBaseURL.appending(path: "api/web_search"), body: Body(query: query, max_results: maxResults), apiKey: apiKey)
            let results = try JSONDecoder().decode(Response.self, from: data).results ?? []
            return results.compactMap { result in
                guard let url = result.url, !url.isEmpty else { return nil }
                return WebResult(title: result.title ?? url, url: url, content: result.content ?? "")
            }
        case .searxng:
            guard let searxngURL else { throw WebSearchError.missingServer }
            var components = URLComponents(url: searxngURL.appending(path: "search"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "format", value: "json")]
            guard let url = components?.url else { throw WebSearchError.invalidURL(searxngURL.absoluteString) }
            struct Response: Decodable {
                struct Result: Decodable {
                    let title: String?
                    let url: String?
                    let content: String?
                }
                let results: [Result]?
            }
            let data = try await get(url)
            let results = try JSONDecoder().decode(Response.self, from: data).results ?? []
            return results.prefix(maxResults).compactMap { result in
                guard let url = result.url, !url.isEmpty else { return nil }
                return WebResult(title: result.title ?? url, url: url, content: result.content ?? "")
            }
        }
    }

    func fetch(_ address: String) async throws -> WebPage {
        guard let url = URL(string: address), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            throw WebSearchError.invalidURL(address)
        }
        if provider == .ollama, let apiKey, !apiKey.isEmpty {
            struct Body: Encodable { let url: String }
            struct Response: Decodable {
                let title: String?
                let content: String?
            }
            let data = try await post(ollamaBaseURL.appending(path: "api/web_fetch"), body: Body(url: address), apiKey: apiKey)
            let page = try JSONDecoder().decode(Response.self, from: data)
            return WebPage(title: page.title ?? address, content: page.content ?? "")
        }
        // SearXNG ne lit pas les pages : on les télécharge directement.
        let data = try await get(url)
        let html = String(decoding: data, as: UTF8.self)
        let extracted = HTMLText.extract(html)
        return WebPage(title: extracted.title.isEmpty ? address : extracted.title, content: extracted.text)
    }

    private func post(_ url: URL, body: some Encodable, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (Macintosh) OllamaChat", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WebSearchError.http(status: http.statusCode, message: OllamaClient.errorMessage(in: data))
        }
        return data
    }

    /// Résultats présentés au modèle, numérotés comme les sources affichées.
    static func formatResults(_ results: [(tag: String, result: WebResult)], query: String) -> String {
        guard !results.isEmpty else { return "Aucun résultat pour « \(query) »." }
        var text = "Résultats de la recherche « \(query) » :\n"
        for (tag, result) in results {
            text += "\n[\(tag)] \(result.title)\n\(result.url)\n\(result.content.prefix(700))\n"
        }
        return text
    }
}

/// Texte lisible d’une page HTML (sans scripts, styles ni balises).
enum HTMLText {
    static func extract(_ html: String) -> (title: String, text: String) {
        let title = firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html).map(decodeEntities)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var text = html
        for pattern in [#"<!--.*?-->"#, #"<(script|style|noscript|svg|head|nav|footer)\b[^>]*>.*?</\1>"#] {
            text = replace(pattern, in: text, with: " ")
        }
        text = replace(#"<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article)\b[^>]*>"#, in: text, with: "\n")
        text = replace(#"<[^>]+>"#, in: text, with: " ")
        text = decodeEntities(text)
        text = replace(#"[ \t\u00A0]+"#, in: text, with: " ")
        text = replace(#"\s*\n\s*"#, in: text, with: "\n")
        text = replace(#"\n{3,}"#, in: text, with: "\n\n")
        return (title, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func decodeEntities(_ text: String) -> String {
        // Entités numériques d’abord (&#233; ou &#xE9;), puis nommées, « &amp; » en dernier :
        // « &amp;lt; » doit donner « &lt; », pas « < ».
        var result = text
        if let regex = try? NSRegularExpression(pattern: #"&#([xX]?)([0-9A-Fa-f]+);"#) {
            let nsText = result as NSString
            var output = ""
            var cursor = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: nsText.length)) {
                output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let isHex = !nsText.substring(with: match.range(at: 1)).isEmpty
                let digits = nsText.substring(with: match.range(at: 2))
                if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    output.unicodeScalars.append(scalar)
                } else {
                    output += nsText.substring(with: match.range)
                }
                cursor = match.range.location + match.range.length
            }
            output += nsText.substring(from: cursor)
            result = output
        }
        let named = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "),
                     ("&eacute;", "é"), ("&egrave;", "è"), ("&agrave;", "à"), ("&ccedil;", "ç"), ("&ecirc;", "ê"),
                     ("&rsquo;", "’"), ("&laquo;", "«"), ("&raquo;", "»"), ("&amp;", "&")]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return text
        }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges > 1
        else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }
}

/// Accès minimal au trousseau macOS (clé API de la recherche web).
enum Keychain {
    private static let service = "com.ollamachat.desktop"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        delete(account: account)
        guard !value.isEmpty else { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
