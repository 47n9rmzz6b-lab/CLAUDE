import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Général", systemImage: "gearshape") }
            GenerationSettings()
                .tabItem { Label("Génération", systemImage: "slider.horizontal.3") }
            PersonalizationSettings()
                .tabItem { Label("Personnalisation", systemImage: "person.crop.circle") }
            MemorySettings()
                .tabItem { Label("Mémoire", systemImage: "brain.head.profile") }
            WebSearchSettings()
                .tabItem { Label("Recherche web", systemImage: "globe") }
            DocumentSettings()
                .tabItem { Label("Documents", systemImage: "doc.text.magnifyingglass") }
            DictationSettings()
                .tabItem { Label("Dictée", systemImage: "mic") }
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - Général

private struct GeneralSettings: View {
    @Environment(ChatStore.self) private var store
    @AppStorage(SettingsKey.serverURL) private var serverURL = AppDefaults.serverURL
    @AppStorage(SettingsKey.serifResponses) private var serifResponses = true
    @AppStorage(SettingsKey.autoTitles) private var autoTitles = true
    @AppStorage(SettingsKey.quickEntryShortcut) private var shortcut = QuickEntryShortcut.optionSpace.rawValue
    @State private var shortcutUnavailable = false

    var body: some View {
        Form {
            Section {
                TextField("Adresse", text: $serverURL, prompt: Text(AppDefaults.serverURL))
                    .onSubmit(refresh)
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Tester la connexion", action: refresh)
                }
            } header: {
                Text("Serveur Ollama")
            } footer: {
                Text("Par défaut, Ollama écoute sur http://localhost:11434. Indiquez une autre adresse pour utiliser Ollama sur une autre machine (lancé avec OLLAMA_HOST=0.0.0.0).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Raccourci", selection: $shortcut) {
                    ForEach(QuickEntryShortcut.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                if shortcutUnavailable {
                    Text("Ce raccourci est déjà utilisé par une autre application : choisissez-en un autre.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Saisie rapide")
            } footer: {
                Text("Depuis n’importe quelle application, le raccourci ouvre un champ pour poser une question sans quitter ce que vous faites. L’app Claude utilise aussi ⌥ Espace : choisissez un autre raccourci si vous avez les deux.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Conversations") {
                Toggle("Titres générés par le modèle", isOn: $autoTitles)
                Toggle("Police à empattements pour les réponses", isOn: $serifResponses)
            }
        }
        .formStyle(.grouped)
        .onChange(of: serverURL) { refresh() }
        .onChange(of: shortcut) {
            let option = QuickEntryShortcut(rawValue: shortcut) ?? .optionSpace
            shortcutUnavailable = !HotKeyCenter.shared.register(option)
        }
    }

    private func refresh() {
        Task { await store.refreshModels() }
    }

    private var statusColor: Color {
        switch store.connection {
        case .connected: return .green
        case .unreachable: return .red
        case .unknown: return .gray
        }
    }

    private var statusText: String {
        switch store.connection {
        case .connected: return "Connecté · \(store.models.count) modèle(s) installé(s)"
        case .unreachable(let message): return message
        case .unknown: return "Connexion…"
        }
    }
}

// MARK: - Génération

private struct GenerationSettings: View {
    @AppStorage(SettingsKey.useCustomTemperature) private var useCustomTemperature = false
    @AppStorage(SettingsKey.temperature) private var temperature = AppDefaults.temperature
    @AppStorage(SettingsKey.contextLength) private var contextLength = AppDefaults.contextLength

    var body: some View {
        Form {
            Section {
                Picker("Taille du contexte", selection: $contextLength) {
                    Text("Valeur d’Ollama").tag(0)
                    ForEach(ContextGauge.sizes, id: \.self) { length in
                        Text("\(length.formatted()) jetons").tag(length)
                    }
                }
            } header: {
                Text("Mémoire de travail")
            } footer: {
                Text("Nombre de jetons que le modèle garde en tête (conversation, instructions, documents). Au-delà, Ollama oublie le début sans prévenir ; plus grand, il consomme davantage de mémoire. Avec la recherche web ou des documents, au moins 16 384 jetons sont utilisés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Imposer une température", isOn: $useCustomTemperature)
                if useCustomTemperature {
                    HStack {
                        Slider(value: $temperature, in: 0...2, step: 0.05) {
                            Text("Température")
                        }
                        Text(temperature, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Température")
            } footer: {
                Text("Chaque profil de réponse (Rigoureux, Code, Créatif…) règle sa propre température. Activez cette option pour imposer la même à tous.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Profils de réponse") {
                ForEach(ResponseProfile.all) { profile in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                            Text(profile.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: profile.icon)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Personnalisation

private struct PersonalizationSettings: View {
    @AppStorage(SettingsKey.aboutMe) private var aboutMe = ""
    @AppStorage(SettingsKey.responseStyle) private var responseStyle = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $aboutMe)
                    .font(.body)
                    .frame(minHeight: 100)
            } header: {
                Text("À propos de moi")
            } footer: {
                Text("Ce que le modèle doit savoir de vous : prénom, métier, niveau, équipement… Par exemple « Je m’appelle Anka, je suis développeuse, j’ai un Mac mini M4 ».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                TextEditor(text: $responseStyle)
                    .font(.body)
                    .frame(minHeight: 100)
            } header: {
                Text("Comment me répondre")
            } footer: {
                Text("Vos préférences de style, envoyées dans chaque conversation. Par exemple « Réponds en français, de façon concise, avec des exemples concrets ».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Mémoire

private struct MemorySettings: View {
    @Environment(ChatStore.self) private var store
    @AppStorage(SettingsKey.memoryEnabled) private var memoryEnabled = true
    @AppStorage(SettingsKey.memoryAutoExtract) private var autoExtract = true
    @State private var newMemory = ""
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Utiliser la mémoire dans les réponses", isOn: $memoryEnabled)
                Toggle("Retenir automatiquement les informations utiles", isOn: $autoExtract)
                    .disabled(!memoryEnabled)
            } footer: {
                Text("Dites « Retiens que… » ou « Oublie… » dans une conversation, ou laissez le modèle relever lui-même ce qui mérite d’être retenu. Tout reste sur ce Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Souvenirs (\(store.memory.memories.count))") {
                if store.memory.memories.isEmpty {
                    Text("Aucun souvenir pour l’instant.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.memory.memories) { memory in
                    HStack(alignment: .firstTextBaseline) {
                        Text(memory.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            store.memory.remove(memory.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Oublier ce souvenir")
                    }
                }
                HStack {
                    TextField("Ajouter un souvenir", text: $newMemory)
                        .onSubmit(addMemory)
                    Button("Ajouter", action: addMemory)
                        .disabled(newMemory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !store.memory.memories.isEmpty {
                Section {
                    Button("Tout oublier…", role: .destructive) { confirmClear = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Oublier tous les souvenirs ?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Tout oublier", role: .destructive) { store.memory.removeAll() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func addMemory() {
        store.memory.add(newMemory)
        newMemory = ""
    }
}

// MARK: - Recherche web

private struct WebSearchSettings: View {
    @AppStorage(SettingsKey.webSearchProvider) private var provider = WebSearchProvider.ollama.rawValue
    @AppStorage(SettingsKey.searxngURL) private var searxngURL = ""
    @State private var apiKey = Keychain.read(account: WebSearchService.keychainAccount) ?? ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                Picker("Service", selection: $provider) {
                    ForEach(WebSearchProvider.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                if provider == WebSearchProvider.ollama.rawValue {
                    SecureField("Clé API", text: $apiKey)
                        .onSubmit(saveKey)
                    HStack {
                        Link("Créer une clé sur ollama.com ↗", destination: URL(string: "https://ollama.com/settings/keys")!)
                            .font(.callout)
                        Spacer()
                        Button("Enregistrer", action: saveKey)
                    }
                } else {
                    TextField("Adresse du serveur", text: $searxngURL, prompt: Text("http://localhost:8888"))
                }
                HStack {
                    Button(isTesting ? "Test en cours…" : "Tester une recherche", action: test)
                        .disabled(isTesting)
                    if let testResult {
                        Text(testResult)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Recherche sur Internet")
            } footer: {
                Text("Activez le globe dans la zone de saisie pour autoriser le modèle à chercher. Les modèles qui gèrent les outils (qwen3, gpt-oss, llama3.1…) cherchent eux-mêmes ; pour les autres, l’app cherche avant de poser la question. Les requêtes quittent votre Mac et passent par le service choisi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func saveKey() {
        Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: WebSearchService.keychainAccount)
        testResult = "Clé enregistrée dans le trousseau."
    }

    private func test() {
        if provider == WebSearchProvider.ollama.rawValue { saveKey() }
        isTesting = true
        testResult = nil
        Task {
            do {
                let results = try await WebSearchService.current().search("Ollama", maxResults: 3)
                testResult = "Ça marche : \(results.count) résultat(s)."
            } catch {
                testResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isTesting = false
        }
    }
}

// MARK: - Documents

private struct DocumentSettings: View {
    @Environment(ChatStore.self) private var store
    @AppStorage(SettingsKey.embeddingModel) private var embeddingModel = ""

    var body: some View {
        Form {
            Section {
                if store.embeddingModels.isEmpty {
                    Text("Aucun modèle d’indexation installé : les passages sont retrouvés par mots-clés.")
                        .foregroundStyle(.secondary)
                    Button("Installer embeddinggemma (environ 600 Mo)") {
                        store.pullModel("embeddinggemma")
                        store.showModelManager = true
                    }
                } else {
                    Picker("Modèle d’indexation", selection: $embeddingModel) {
                        Text("Automatique").tag("")
                        ForEach(store.embeddingModels) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                    if let active = store.activeEmbeddingModel {
                        Text("Utilisé : \(active)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Réponses à partir de vos documents")
            } footer: {
                Text("Joignez des PDF, textes, Markdown ou documents Word avec le trombone, ou glissez-les dans la fenêtre. Les documents courts sont donnés en entier au modèle ; pour les longs, l’app retrouve les passages utiles à chaque question. Un modèle d’indexation (embeddinggemma, nomic-embed-text…) donne de meilleurs résultats que la recherche par mots-clés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Dictée

private struct DictationSettings: View {
    @AppStorage(SettingsKey.dictationLocale) private var locale = "fr-FR"

    private let languages: [(String, String)] = [
        ("fr-FR", "Français (France)"),
        ("fr-CA", "Français (Canada)"),
        ("en-US", "Anglais (États-Unis)"),
        ("en-GB", "Anglais (Royaume-Uni)"),
        ("es-ES", "Espagnol"),
        ("de-DE", "Allemand"),
        ("it-IT", "Italien"),
        ("pt-BR", "Portugais (Brésil)"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Langue", selection: $locale) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
            } header: {
                Text("Dictée")
            } footer: {
                Text("Cliquez sur le micro de la zone de saisie et parlez : le texte s’écrit au fur et à mesure. La reconnaissance se fait sur ce Mac quand la langue le permet ; sinon, elle passe par les serveurs d’Apple. macOS demande l’accès au micro la première fois.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
