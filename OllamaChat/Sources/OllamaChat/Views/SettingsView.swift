import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Général", systemImage: "gearshape") }
            GenerationSettings()
                .tabItem { Label("Génération", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 540, height: 430)
    }
}

private struct GeneralSettings: View {
    @Environment(ChatStore.self) private var store
    @AppStorage(SettingsKey.serverURL) private var serverURL = AppDefaults.serverURL
    @AppStorage(SettingsKey.serifResponses) private var serifResponses = true

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
                        .fixedSize(horizontal: false, vertical: true)
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

            Section("Apparence") {
                Toggle("Police à empattements pour les réponses", isOn: $serifResponses)
            }
        }
        .formStyle(.grouped)
        .onChange(of: serverURL) { refresh() }
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

private struct GenerationSettings: View {
    @AppStorage(SettingsKey.systemPrompt) private var systemPrompt = ""
    @AppStorage(SettingsKey.useCustomTemperature) private var useCustomTemperature = false
    @AppStorage(SettingsKey.temperature) private var temperature = AppDefaults.temperature
    @AppStorage(SettingsKey.contextLength) private var contextLength = 0

    private let contextLengths = [2048, 4096, 8192, 16384, 32768, 65536, 131072]

    var body: some View {
        Form {
            Section {
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(minHeight: 100)
            } header: {
                Text("Instructions système")
            } footer: {
                Text("Envoyées au début de chaque conversation, par exemple « Réponds toujours en français, de façon concise. » Laissez vide pour garder celles du modèle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Paramètres") {
                Toggle("Température personnalisée", isOn: $useCustomTemperature)
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
                Picker("Longueur du contexte", selection: $contextLength) {
                    Text("Valeur par défaut d’Ollama").tag(0)
                    ForEach(contextLengths, id: \.self) { length in
                        Text("\(length.formatted()) jetons").tag(length)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
