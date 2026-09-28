import SwiftUI

/// Télécharger et supprimer des modèles sans passer par `ollama pull` / `ollama rm`.
struct ModelManagerView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var newModel = ""
    @State private var modelToDelete: String?
    @State private var isConfirmingDelete = false

    private let suggestions = ["llama3.2", "gemma3", "qwen3", "mistral", "deepseek-r1", "embeddinggemma"]

    private var canPull: Bool {
        !newModel.trimmingCharacters(in: .whitespaces).isEmpty && store.pull?.isActive != true && store.isConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Modèles")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    Task { await store.refreshModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Actualiser")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Télécharger un modèle")
                    .font(.headline)
                HStack {
                    TextField("Nom du modèle, par exemple llama3.2 ou qwen3:8b", text: $newModel)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(startPull)
                    Button("Télécharger", action: startPull)
                        .disabled(!canPull)
                }
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { name in
                        Button(name) { newModel = name }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Spacer()
                    Link("Bibliothèque Ollama ↗", destination: URL(string: "https://ollama.com/library")!)
                        .font(.callout)
                }
                if let pull = store.pull {
                    PullStatusView(pull: pull)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Modèles installés")
                    .font(.headline)
                if store.models.isEmpty {
                    Text(store.isConnected ? "Aucun modèle installé." : "Ollama est injoignable.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    List {
                        ForEach(store.models) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.body.weight(.medium))
                                    let details = capabilitySummary(for: model)
                                    if !details.isEmpty {
                                        Text(details)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    modelToDelete = model.name
                                    isConfirmingDelete = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Supprimer ce modèle")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .frame(minHeight: 180)
                }
                if let error = store.modelError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 580, height: 560)
        .confirmationDialog(
            "Supprimer « \(modelToDelete ?? "") » ?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let modelToDelete {
                    Task { await store.deleteModel(modelToDelete) }
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le modèle sera effacé du disque. Vous pourrez le télécharger à nouveau plus tard.")
        }
    }

    private func capabilitySummary(for model: OllamaModel) -> String {
        let info = store.info(for: model.name)
        var parts: [String] = []
        if !model.summary.isEmpty { parts.append(model.summary) }
        if info.isEmbeddingModel { parts.append("indexation de documents") }
        if info.supportsThinking { parts.append("réflexion") }
        if info.supportsVision { parts.append("images") }
        if info.supportsTools { parts.append("outils") }
        return parts.joined(separator: " · ")
    }

    private func startPull() {
        guard canPull else { return }
        store.pullModel(newModel)
        newModel = ""
    }
}

private struct PullStatusView: View {
    @Environment(ChatStore.self) private var store
    let pull: ChatStore.PullState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer()
                if pull.isActive {
                    Button("Annuler") { store.cancelPull() }
                        .controlSize(.small)
                } else {
                    Button {
                        store.dismissPullStatus()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Masquer")
                }
            }
            if pull.isActive {
                ProgressView(value: pull.fraction)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if let error = pull.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(pull.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var title: String {
        if pull.error != nil { return "Échec du téléchargement de \(pull.model)" }
        if pull.isFinished { return "\(pull.model) est installé" }
        return "Téléchargement de \(pull.model)"
    }

    private var detail: String {
        guard pull.total > 0 else { return pull.status }
        let completed = ByteCountFormatter.string(fromByteCount: pull.completed, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: pull.total, countStyle: .file)
        let percent = Int(((pull.fraction ?? 0) * 100).rounded())
        return "\(pull.status) \(completed) sur \(total) (\(percent) %)"
    }
}
