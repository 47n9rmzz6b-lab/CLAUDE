import SwiftUI

struct SidebarView: View {
    @Environment(ChatStore.self) private var store

    @State private var search = ""
    @State private var renameTarget: UUID?
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var deleteTarget: UUID?
    @State private var isConfirmingDelete = false

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedID) {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.conversations) { conversation in
                        Text(conversation.title)
                            .lineLimit(1)
                            .tag(conversation.id)
                            .contextMenu {
                                Button("Renommer…") { startRenaming(conversation) }
                                Button("Supprimer…", role: .destructive) { confirmDelete(conversation.id) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: "Rechercher")
        .overlay {
            if store.conversations.isEmpty {
                Text("Vos conversations apparaîtront ici.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            newConversationButton
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
        .onDeleteCommand {
            if let id = store.selectedID { confirmDelete(id) }
        }
        .alert("Renommer la conversation", isPresented: $isRenaming) {
            TextField("Titre", text: $renameText)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") {
                if let renameTarget { store.rename(renameTarget, to: renameText) }
            }
        }
        .confirmationDialog("Supprimer cette conversation ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let deleteTarget { store.delete(deleteTarget) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action est définitive.")
        }
    }

    private var newConversationButton: some View {
        Button {
            store.newConversation()
        } label: {
            Label("Nouvelle conversation", systemImage: "plus")
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(store.selectedID == nil ? Theme.accent.opacity(0.14) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .help("Nouvelle conversation (⌘N)")
    }

    private func startRenaming(_ conversation: Conversation) {
        renameTarget = conversation.id
        renameText = conversation.title
        isRenaming = true
    }

    private func confirmDelete(_ id: UUID) {
        deleteTarget = id
        isConfirmingDelete = true
    }

    // MARK: - Regroupement par date, comme dans l’application Claude

    private struct SidebarSection: Identifiable {
        let title: String
        var conversations: [Conversation]
        var id: String { title }
    }

    private var sections: [SidebarSection] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? store.conversations : store.conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query)
                || conversation.messages.contains { $0.content.localizedCaseInsensitiveContains(query) }
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let titles = ["Aujourd’hui", "Hier", "7 derniers jours", "30 derniers jours", "Plus ancien"]
        var buckets = Array(repeating: [Conversation](), count: titles.count)

        for conversation in filtered.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let day = calendar.startOfDay(for: conversation.updatedAt)
            let age = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let bucket: Int
            switch age {
            case ..<1: bucket = 0
            case 1: bucket = 1
            case 2..<7: bucket = 2
            case 7..<30: bucket = 3
            default: bucket = 4
            }
            buckets[bucket].append(conversation)
        }

        return zip(titles, buckets).compactMap { title, conversations in
            conversations.isEmpty ? nil : SidebarSection(title: title, conversations: conversations)
        }
    }
}

private struct SidebarFooter: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if let pull = store.pull, pull.isActive {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Téléchargement de \(pull.model)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: pull.fraction)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    store.showModelManager = true
                } label: {
                    Image(systemName: "square.stack.3d.up")
                }
                .buttonStyle(.borderless)
                .help("Gérer les modèles")
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Réglages")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
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
        case .connected:
            let count = store.models.count
            if count == 0 { return "Ollama · aucun modèle" }
            return "Ollama · \(count) modèle\(count > 1 ? "s" : "")"
        case .unreachable:
            return "Ollama injoignable"
        case .unknown:
            return "Connexion à Ollama…"
        }
    }
}
