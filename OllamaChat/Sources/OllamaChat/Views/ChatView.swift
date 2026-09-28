import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @AppStorage(SettingsKey.serifResponses) private var serifResponses = true
    @State private var draft = ""
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if let conversation = store.selectedConversation, !conversation.messages.isEmpty {
                VStack(spacing: 0) {
                    MessageListView(
                        conversation: conversation,
                        streamingMessageID: store.generatingID == conversation.id ? conversation.messages.last?.id : nil,
                        editingMessageID: store.editingMessageID,
                        serif: serifResponses
                    )
                    VStack(spacing: 8) {
                        StatusBanners(draft: draft)
                        ComposerView(
                            text: $draft,
                            takesFocus: !store.selectionChangedWithKeyboard,
                            isGeneratingHere: store.generatingID == conversation.id
                        ) { store.send($0) }
                    }
                    .frame(maxWidth: 780)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 18)
                }
            } else {
                WelcomeView(draft: $draft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Theme.accent.opacity(0.05))
                    .overlay(
                        Label("Déposez des images ou des documents", systemImage: "paperclip")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    )
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: handleDrop)
        .navigationTitle(store.selectedConversation?.title ?? "Nouvelle conversation")
        .navigationSubtitle(store.currentModel)
    }

    /// Fichiers ou images déposés sur la fenêtre.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let store = store
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in store.attach(urls: [url]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in store.attachImage(data: data) }
                }
            }
        }
        return handled
    }
}

private struct WelcomeView: View {
    @Environment(ChatStore.self) private var store
    @Binding var draft: String

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "sparkle")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
                Text(greeting)
                    .font(.system(size: 34, design: .serif))
            }
            VStack(spacing: 10) {
                ComposerView(text: $draft, takesFocus: true, isGeneratingHere: false) { store.send($0) }
                StatusBanners(draft: draft)
            }
            .frame(maxWidth: 680)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = (5..<18).contains(hour) ? "Bonjour" : "Bonsoir"
        let firstName = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? hello : "\(hello), \(firstName)"
    }
}

/// Bandeaux d’information au-dessus (ou au-dessous) de la zone de saisie.
struct StatusBanners: View {
    let draft: String

    var body: some View {
        VStack(spacing: 8) {
            ConnectionBanner()
            ContextOverflowBanner(draft: draft)
            WebSearchSetupBanner()
        }
    }
}

/// Signale qu’Ollama est injoignable ou qu’aucun modèle n’est installé, avec l’action utile.
struct ConnectionBanner: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        switch store.connection {
        case .unreachable(let message):
            InfoBanner(icon: "bolt.horizontal.circle", tint: .orange, message: message) {
                if ChatStore.ollamaAppURL != nil {
                    Button("Ouvrir Ollama") { store.launchOllama() }
                } else {
                    Link("Télécharger Ollama", destination: URL(string: "https://ollama.com/download")!)
                }
                Button("Réessayer") {
                    Task { await store.refreshModels() }
                }
            }
        case .connected where store.chatModels.isEmpty:
            InfoBanner(
                icon: "square.and.arrow.down",
                tint: Theme.accent,
                message: "Aucun modèle n’est installé. Téléchargez-en un pour commencer."
            ) {
                Button("Télécharger un modèle…") { store.showModelManager = true }
            }
        default:
            EmptyView()
        }
    }
}

/// La conversation dépasse la mémoire de travail du modèle : le début serait oublié.
struct ContextOverflowBanner: View {
    @Environment(ChatStore.self) private var store
    @AppStorage(SettingsKey.contextLength) private var contextSetting = AppDefaults.contextLength
    let draft: String

    var body: some View {
        let used = store.estimatedPromptTokens(for: store.selectedConversation, draft: draft)
        if let limit = store.contextLength(model: store.currentModel, webSearch: store.currentWebSearch, hasDocuments: !store.currentDocuments.isEmpty),
           used > Int(Double(limit) * 0.9) {
            let next = ContextGauge.sizes.first { $0 > limit && $0 >= used + 1024 }
            InfoBanner(
                icon: "gauge.with.dots.needle.100percent",
                tint: .orange,
                message: used > limit
                    ? "La conversation dépasse la mémoire de travail du modèle (environ \(ContextGauge.compact(used)) sur \(ContextGauge.compact(limit)) jetons) : le début sera oublié."
                    : "La conversation approche la limite de la mémoire de travail du modèle (environ \(ContextGauge.compact(used)) sur \(ContextGauge.compact(limit)) jetons)."
            ) {
                if let next {
                    Button("Passer à \(ContextGauge.compact(next))") { contextSetting = next }
                }
                Button("Nouvelle conversation") { store.newConversation() }
            }
        }
    }
}

/// Recherche web activée sans service configuré.
struct WebSearchSetupBanner: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        if store.currentWebSearch, !store.webSearchConfigured {
            InfoBanner(
                icon: "globe",
                tint: .orange,
                message: "La recherche web n’est pas encore configurée : ajoutez une clé API Ollama (gratuite) ou l’adresse d’un serveur SearXNG."
            ) {
                SettingsLink { Text("Réglages…") }
                Button("Désactiver") { store.setWebSearch(false) }
            }
        }
    }
}

/// Bandeau coloré avec un message et des actions.
struct InfoBanner<Actions: View>: View {
    let icon: String
    let tint: Color
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(tint)
            // Pas de .fixedSize(vertical:) ici : pour calculer la hauteur minimale de la fenêtre,
            // SwiftUI propose une largeur quasi nulle, et le texte replié à un caractère par ligne
            // rendait toute l’interface plus haute que la fenêtre.
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.25)))
    }
}
