import AppKit
import Foundation

/// Connexion à Ollama, liste des modèles et de leurs capacités, téléchargements.
extension ChatStore {
    /// Modèles capables de converser (les modèles d’indexation sont exclus).
    var chatModels: [OllamaModel] {
        models.filter { !info(for: $0.name).isEmbeddingModel }
    }

    /// Modèles d’indexation installés, pour les documents.
    var embeddingModels: [OllamaModel] {
        models.filter { info(for: $0.name).isEmbeddingModel }
    }

    func info(for model: String) -> ModelInfo {
        modelInfo[model] ?? ModelInfo.guessed(for: model)
    }

    /// Interroge Ollama régulièrement : la liste des modèles reste à jour (y compris après un
    /// `ollama pull` fait dans le Terminal) et l’app se reconnecte seule quand Ollama démarre.
    func monitorConnection() async {
        while !Task.isCancelled {
            await refreshModels()
            let delay: Duration = isConnected ? .seconds(20) : .seconds(4)
            try? await Task.sleep(for: delay)
        }
    }

    func refreshModels() async {
        do {
            let client = try makeClient()
            let list = try await client.listModels()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await loadModelInfo(for: list, client: client)
            if models != list { models = list }
            if connection != .connected { connection = .connected }
            let chatNames = chatModels.map(\.name)
            if !chatNames.contains(draftModel), let first = chatNames.first {
                draftModel = first
            }
            onConnected()
        } catch {
            let message = describe(error)
            if connection != .unreachable(message) { connection = .unreachable(message) }
            if !models.isEmpty { models = [] }
        }
    }

    /// Récupère les capacités des modèles nouveaux ou modifiés.
    private func loadModelInfo(for list: [OllamaModel], client: OllamaClient) async {
        let stale = list.filter { model in
            modelInfo[model.name] == nil || modelInfoDigests[model.name] != (model.digest ?? "")
        }
        guard !stale.isEmpty else { return }
        let results = await withTaskGroup(of: (String, String, ModelInfo?).self) { group in
            for model in stale {
                group.addTask {
                    let info = try? await client.modelInfo(model.name)
                    return (model.name, model.digest ?? "", info)
                }
            }
            var collected: [(String, String, ModelInfo?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var updated = modelInfo
        for (name, digest, info) in results {
            updated[name] = info ?? ModelInfo.guessed(for: name)
            modelInfoDigests[name] = digest
        }
        if updated != modelInfo { modelInfo = updated }
    }

    func pullModel(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, pull?.isActive != true else { return }
        modelError = nil
        pull = PullState(model: name, status: "Connexion…")
        pullTask = Task { [weak self] in
            await self?.runPull(name)
        }
    }

    func cancelPull() {
        pullTask?.cancel()
        pullTask = nil
        pull = nil
    }

    func dismissPullStatus() {
        if pull?.isActive != true { pull = nil }
    }

    private func runPull(_ name: String) async {
        do {
            let client = try makeClient()
            for try await progress in client.pull(model: name) {
                guard var state = pull, state.model == name else { return }
                if let status = progress.status { state.status = Self.pullStatusText(status) }
                if let total = progress.total, total > 0 {
                    state.total = total
                    state.completed = progress.completed ?? 0
                }
                pull = state
            }
            guard !Task.isCancelled else { return }
            pull?.isFinished = true
            pull?.status = "Le modèle est installé et prêt à l’emploi."
            await refreshModels()
        } catch {
            guard !Task.isCancelled else { return }
            pull?.error = describe(error)
        }
        pullTask = nil
    }

    func deleteModel(_ name: String) async {
        modelError = nil
        do {
            try await makeClient().deleteModel(name)
        } catch {
            modelError = describe(error)
        }
        await refreshModels()
    }

    /// Emplacement de l’application Ollama, si elle est installée.
    static var ollamaAppURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") {
            return url
        }
        return ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    func launchOllama() {
        guard let url = Self.ollamaAppURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        Task {
            try? await Task.sleep(for: .seconds(3))
            await refreshModels()
        }
    }

    static func pullStatusText(_ status: String) -> String {
        switch status {
        case "pulling manifest": return "Récupération du manifeste…"
        case "verifying sha256 digest": return "Vérification…"
        case "writing manifest": return "Écriture du manifeste…"
        case "removing any unused layers", "removing unused layers": return "Nettoyage…"
        case "success": return "Terminé"
        default:
            if status.hasPrefix("pulling") || status.hasPrefix("downloading") { return "Téléchargement…" }
            return status
        }
    }
}
