import AppKit
import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @AppStorage(SettingsKey.serifResponses) private var serifResponses = true
    @State private var draft = ""

    var body: some View {
        Group {
            if let conversation = store.selectedConversation, !conversation.messages.isEmpty {
                VStack(spacing: 0) {
                    MessageListView(
                        conversation: conversation,
                        streamingMessageID: store.generatingID == conversation.id ? conversation.messages.last?.id : nil,
                        serif: serifResponses
                    )
                    VStack(spacing: 8) {
                        ConnectionBanner()
                        ComposerView(
                            text: $draft,
                            forceFocus: false,
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
        .navigationTitle(store.selectedConversation?.title ?? "Nouvelle conversation")
        .navigationSubtitle(store.currentModel)
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
                ComposerView(text: $draft, forceFocus: true, isGeneratingHere: false) { store.send($0) }
                ConnectionBanner()
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

/// Signale qu’Ollama est injoignable ou qu’aucun modèle n’est installé, avec l’action utile.
struct ConnectionBanner: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        switch store.connection {
        case .unreachable(let message):
            banner(icon: "bolt.horizontal.circle", tint: .orange, message: message) {
                if ChatStore.ollamaAppURL != nil {
                    Button("Ouvrir Ollama") { store.launchOllama() }
                } else {
                    Link("Télécharger Ollama", destination: URL(string: "https://ollama.com/download")!)
                }
                Button("Réessayer") {
                    Task { await store.refreshModels() }
                }
            }
        case .connected where store.models.isEmpty:
            banner(
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

    private func banner<Actions: View>(
        icon: String,
        tint: Color,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
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
