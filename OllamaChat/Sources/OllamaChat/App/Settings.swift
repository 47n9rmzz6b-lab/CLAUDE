import Foundation

/// Clés des réglages enregistrés dans UserDefaults (partagées avec @AppStorage).
enum SettingsKey {
    static let serverURL = "serverURL"
    static let defaultModel = "defaultModel"
    /// Ancien réglage « Instructions système », repris dans `responseStyle`.
    static let systemPrompt = "systemPrompt"
    static let useCustomTemperature = "useCustomTemperature"
    static let temperature = "temperature"
    static let contextLength = "contextLength"
    static let serifResponses = "serifResponses"
    static let lastConversationID = "lastConversationID"

    // Réglages proposés pour une nouvelle conversation (repris de la dernière utilisée).
    static let lastProfileID = "lastProfileID"
    static let lastThinking = "lastThinking"
    static let lastWebSearch = "lastWebSearch"

    // Personnalisation et mémoire.
    static let aboutMe = "aboutMe"
    static let responseStyle = "responseStyle"
    static let memoryEnabled = "memoryEnabled"
    static let memoryAutoExtract = "memoryAutoExtract"

    // Recherche web.
    static let webSearchProvider = "webSearchProvider"
    static let searxngURL = "searxngURL"
    static let ollamaWebSearchURL = "ollamaWebSearchURL"

    // Documents.
    static let embeddingModel = "embeddingModel"

    // Divers.
    static let autoTitles = "autoTitles"
    static let quickEntryShortcut = "quickEntryShortcut"
    static let dictationLocale = "dictationLocale"
}

enum AppDefaults {
    static let serverURL = "http://localhost:11434"
    static let temperature = 0.8
    /// Taille de contexte envoyée à Ollama : assez grande pour de vraies conversations,
    /// sans trop charger la mémoire.
    static let contextLength = 8192
    /// Minimum quand la recherche web ou des documents sont utilisés.
    static let contextLengthWithTools = 16384
    static let ollamaWebSearchURL = "https://ollama.com"

    static func register() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            SettingsKey.serverURL: serverURL,
            SettingsKey.temperature: temperature,
            SettingsKey.contextLength: contextLength,
            SettingsKey.serifResponses: true,
            SettingsKey.lastProfileID: ResponseProfile.balanced.id,
            SettingsKey.lastThinking: ThinkingSetting.on.rawValue,
            SettingsKey.memoryEnabled: true,
            SettingsKey.memoryAutoExtract: true,
            SettingsKey.webSearchProvider: WebSearchProvider.ollama.rawValue,
            SettingsKey.ollamaWebSearchURL: ollamaWebSearchURL,
            SettingsKey.autoTitles: true,
            SettingsKey.quickEntryShortcut: QuickEntryShortcut.optionSpace.rawValue,
            SettingsKey.dictationLocale: "fr-FR",
        ])
        // L’ancien réglage « Instructions système » devient « Comment me répondre ».
        if let legacy = defaults.string(forKey: SettingsKey.systemPrompt), !legacy.isEmpty,
           defaults.string(forKey: SettingsKey.responseStyle) == nil {
            defaults.set(legacy, forKey: SettingsKey.responseStyle)
            defaults.removeObject(forKey: SettingsKey.systemPrompt)
        }
    }
}

/// Emplacements des fichiers de l’app.
enum AppPaths {
    /// Dossier de l’app dans « Application Support ».
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appending(path: "OllamaChat", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
