import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Bouton rond et discret de la barre de saisie ; `isOn` le met en couleur.
private struct ComposerIconLabel: View {
    let systemImage: String
    var isOn = false
    var text: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
            if let text {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isOn ? Theme.accent : Color.secondary)
        .padding(.horizontal, text == nil ? 7 : 9)
        .frame(height: 28)
        .background(
            Capsule(style: .continuous)
                .fill(isOn ? Theme.accent.opacity(0.13) : Color.primary.opacity(0.05))
        )
        .contentShape(Capsule())
    }
}

// MARK: - Pièces jointes

struct AttachButton: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        Button {
            store.chooseAttachments()
        } label: {
            ComposerIconLabel(systemImage: "paperclip")
        }
        .buttonStyle(.plain)
        .help("Joindre des images ou des documents (PDF, texte, Word…) — ⌘O")
    }
}

/// Aperçu des images à envoyer et des documents de la conversation.
struct AttachmentStrip: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        let documents = store.currentDocuments
        if !store.pendingImages.isEmpty || !documents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.pendingImages, id: \.self) { name in
                        PendingImageThumbnail(name: name)
                    }
                    ForEach(documents) { document in
                        DocumentChip(document: document)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct PendingImageThumbnail: View {
    @Environment(ChatStore.self) private var store
    let name: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = AttachmentStore.shared.image(named: name) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                store.removePendingImage(name)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .help("Retirer l’image")
        }
    }
}

private struct DocumentChip: View {
    @Environment(ChatStore.self) private var store
    let document: DocumentRef

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(document.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(status)
                    .font(.system(size: 10.5))
                    .foregroundStyle(document.status == .failed ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            if document.status == .indexing {
                ProgressView().controlSize(.mini)
            }
            Button {
                store.removeDocument(document.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Retirer ce document de la conversation")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .frame(maxWidth: 240)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .help(document.error ?? document.name)
    }

    private var status: String {
        switch document.status {
        case .indexing:
            return "Lecture…"
        case .failed:
            return document.error ?? "Illisible"
        case .ready:
            var parts: [String] = []
            if let pages = document.pageCount { parts.append("\(pages) p.") }
            parts.append(document.characterCount > DocumentService.fullTextLimit ? "\(document.chunkCount) passages" : "texte entier")
            if document.embeddingModel != nil { parts.append("indexé") }
            return parts.joined(separator: " · ")
        }
    }
}

// MARK: - Outils

struct WebSearchToggle: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        let isOn = store.currentWebSearch
        Button {
            store.setWebSearch(!isOn)
        } label: {
            ComposerIconLabel(systemImage: "globe", isOn: isOn, text: isOn ? "Web" : nil)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Recherche web activée : le modèle peut chercher sur Internet" : "Autoriser la recherche sur Internet")
    }
}

struct ThinkingControl: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        let info = store.info(for: store.currentModel)
        if info.supportsThinking {
            if info.usesThinkingLevels {
                Menu {
                    Picker("Effort de réflexion", selection: Binding(get: { level }, set: { store.setThinking($0) })) {
                        Text("Faible").tag(ThinkingSetting.low)
                        Text("Moyen").tag(ThinkingSetting.medium)
                        Text("Élevé").tag(ThinkingSetting.high)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Réflexion : \(levelName)", systemImage: "brain")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Effort de réflexion du modèle")
            } else {
                let isOn = store.currentThinking != .off
                Button {
                    store.setThinking(isOn ? .off : .on)
                } label: {
                    ComposerIconLabel(systemImage: "brain", isOn: isOn, text: isOn ? "Réfléchir" : nil)
                }
                .buttonStyle(.plain)
                .help(isOn ? "Le modèle réfléchit avant de répondre (plus lent, plus rigoureux)" : "Réponse directe, sans réflexion préalable")
            }
        }
    }

    private var level: ThinkingSetting {
        switch store.currentThinking {
        case .low, .off: return .low
        case .high: return .high
        case .medium, .on: return .medium
        }
    }

    private var levelName: String {
        switch level {
        case .low: return "faible"
        case .high: return "élevée"
        default: return "moyenne"
        }
    }
}

struct ProfileMenu: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        let current = store.currentProfile
        Menu {
            Picker("Profil de réponse", selection: Binding(get: { current.id }, set: { store.selectProfile($0) })) {
                ForEach(ResponseProfile.all) { profile in
                    Label(profile.name, systemImage: profile.icon).tag(profile.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(current.name, systemImage: current.icon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Profil de réponse : \(current.summary)")
    }
}

// MARK: - Jauge de contexte

struct ContextGauge: View {
    @Environment(ChatStore.self) private var store
    @AppStorage(SettingsKey.contextLength) private var contextSetting = AppDefaults.contextLength
    let draft: String

    @State private var showDetails = false

    static let sizes = [4096, 8192, 16384, 32768, 65536, 131072]

    var body: some View {
        let used = store.estimatedPromptTokens(for: store.selectedConversation, draft: draft)
        let limit = store.contextLength(for: store.selectedConversation)
        let fraction = limit.map { min(1, Double(used) / Double(max($0, 1))) }
        Button {
            showDetails.toggle()
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: fraction ?? 0)
                        .stroke(color(for: fraction), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
                Text(Self.compact(used))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mémoire de travail du modèle : environ \(used) jetons utilisés")
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            details(used: used, limit: limit)
        }
    }

    @ViewBuilder
    private func details(used: Int, limit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mémoire de travail")
                .font(.headline)
            if let limit {
                let percent = Int(Double(used) / Double(max(limit, 1)) * 100)
                Text(verbatim: "Environ \(used.formatted()) jetons sur \(limit.formatted()) (\(percent) %).")
            } else {
                Text(verbatim: "Environ \(used.formatted()) jetons (taille gérée par Ollama).")
            }
            Text("Au-delà de la limite, Ollama oublie le début de la conversation sans prévenir. Agrandir le contexte consomme plus de mémoire.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Taille du contexte", selection: $contextSetting) {
                Text("Valeur d’Ollama").tag(0)
                ForEach(Self.sizes, id: \.self) { size in
                    Text("\(size.formatted()) jetons").tag(size)
                }
            }
            if store.currentWebSearch || !store.currentDocuments.isEmpty {
                Text("Recherche web ou documents : au moins \(AppDefaults.contextLengthWithTools.formatted()) jetons sont utilisés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func color(for fraction: Double?) -> Color {
        guard let fraction else { return .secondary }
        if fraction >= 0.9 { return .red }
        if fraction >= 0.7 { return .orange }
        return Theme.accent
    }

    static func compact(_ value: Int) -> String {
        guard value >= 1000 else { return "\(value)" }
        let thousands = Double(value) / 1000
        return thousands < 10
            ? thousands.formatted(.number.precision(.fractionLength(1))) + " k"
            : "\(Int(thousands.rounded())) k"
    }
}

// MARK: - Dictée

struct DictationButton: View {
    @Environment(ChatStore.self) private var store
    @Binding var text: String
    @State private var baseText = ""

    var body: some View {
        let isActive = store.dictation.isActive
        Button {
            if !isActive { baseText = text }
            store.dictation.toggle { transcript in
                text = baseText.isEmpty ? transcript : baseText + " " + transcript
            }
        } label: {
            Image(systemName: isActive ? "mic.fill" : "mic")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.red : Color.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isActive ? Color.red.opacity(0.12) : Color.clear))
                .symbolEffect(.pulse, options: .repeating, isActive: isActive)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isActive ? "Arrêter la dictée" : "Dicter un message")
    }
}

// MARK: - Modèle

/// Menu de choix du modèle, placé sous la zone de saisie comme dans l’application Claude.
struct ModelPicker: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        Menu {
            if store.chatModels.isEmpty {
                Text("Aucun modèle disponible")
            } else {
                Picker("Modèle", selection: Binding(get: { store.currentModel }, set: { store.selectModel($0) })) {
                    ForEach(store.chatModels) { model in
                        Text(label(for: model.name)).tag(model.name)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Divider()
            Button("Gérer les modèles…") { store.showModelManager = true }
        } label: {
            Text(store.currentModel.isEmpty ? "Choisir un modèle" : store.currentModel)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Modèle utilisé pour cette conversation")
    }

    private func label(for model: String) -> String {
        let info = store.info(for: model)
        var tags: [String] = []
        if info.supportsThinking { tags.append("réflexion") }
        if info.supportsVision { tags.append("images") }
        if info.supportsTools { tags.append("outils") }
        return tags.isEmpty ? model : "\(model)  —  \(tags.joined(separator: ", "))"
    }
}
