import AppKit
import Foundation
import UniformTypeIdentifiers

/// Images et documents joints, modification d’un message envoyé, export.
extension ChatStore {
    // MARK: - Pièces jointes

    /// Fichiers ajoutés (bouton, glisser-déposer, « Ouvrir avec ») : images pour le prochain message,
    /// documents pour la conversation.
    func attach(urls: [URL]) {
        var errors: [String] = []
        for url in urls {
            if AttachmentStore.isImage(url) {
                do {
                    pendingImages.append(try AttachmentStore.shared.importImage(from: url))
                } catch {
                    errors.append(describe(error))
                }
            } else if DocumentService.isDocument(url) {
                attachDocument(url)
            } else {
                errors.append("Format non pris en charge : « \(url.lastPathComponent) ».")
            }
        }
        attachmentError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    /// Fenêtre de choix des fichiers à joindre.
    func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.title = "Joindre des fichiers"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image] + DocumentService.supportedTypes
        guard panel.runModal() == .OK else { return }
        attach(urls: panel.urls)
    }

    func attachImage(data: Data) {
        do {
            pendingImages.append(try AttachmentStore.shared.importImage(data: data))
            attachmentError = nil
        } catch {
            attachmentError = describe(error)
        }
    }

    func removePendingImage(_ name: String) {
        pendingImages.removeAll { $0 == name }
        try? FileManager.default.removeItem(at: AttachmentStore.shared.url(for: name))
    }

    /// Documents de la conversation affichée, ou de l’écran « Nouvelle conversation ».
    var currentDocuments: [DocumentRef] {
        selectedConversation?.documents ?? draftDocuments
    }

    /// Le modèle choisi ne voit pas les images alors qu’il y en a à envoyer.
    var imagesNeedVisionModel: Bool {
        !pendingImages.isEmpty && !currentModel.isEmpty && !info(for: currentModel).supportsVision
    }

    /// Modèle d’indexation : celui des réglages s’il est installé, sinon le premier trouvé.
    var activeEmbeddingModel: String? {
        let names = embeddingModels.map(\.name)
        let chosen = UserDefaults.standard.string(forKey: SettingsKey.embeddingModel) ?? ""
        if !chosen.isEmpty, names.contains(chosen) { return chosen }
        return names.first
    }

    func attachDocument(_ url: URL) {
        let reference = DocumentRef(name: url.lastPathComponent)
        if let selectedID, let index = index(of: selectedID) {
            conversations[index].documents.append(reference)
            save()
        } else {
            draftDocuments.append(reference)
        }
        let client = try? makeClient()
        let embeddingModel = activeEmbeddingModel
        Task { [weak self] in
            do {
                let (index, pageCount) = try await DocumentService.buildIndex(from: url, client: client, embeddingModel: embeddingModel)
                try AttachmentStore.shared.save(index, for: reference.id)
                self?.updateDocument(reference.id) { document in
                    document.status = .ready
                    document.characterCount = index.characterCount
                    document.chunkCount = index.chunks.count
                    document.pageCount = pageCount
                    document.embeddingModel = index.embeddingModel
                }
            } catch {
                let text = self?.describe(error) ?? error.localizedDescription
                self?.updateDocument(reference.id) { document in
                    document.status = .failed
                    document.error = text
                }
            }
        }
    }

    func removeDocument(_ id: UUID) {
        AttachmentStore.shared.removeDocument(id)
        draftDocuments.removeAll { $0.id == id }
        for index in conversations.indices where conversations[index].documents.contains(where: { $0.id == id }) {
            conversations[index].documents.removeAll { $0.id == id }
        }
        save()
    }

    private func updateDocument(_ id: UUID, _ change: (inout DocumentRef) -> Void) {
        if let position = draftDocuments.firstIndex(where: { $0.id == id }) {
            change(&draftDocuments[position])
            return
        }
        for index in conversations.indices {
            if let position = conversations[index].documents.firstIndex(where: { $0.id == id }) {
                change(&conversations[index].documents[position])
                save()
                return
            }
        }
    }

    // MARK: - Modifier un message

    /// Dernier message de l’utilisateur (flèche ↑ dans une zone de saisie vide).
    var lastEditableMessageID: UUID? {
        selectedConversation?.messages.last { $0.role == .user && $0.kind == .normal }?.id
    }

    /// Remplace le texte d’un message de l’utilisateur, efface la suite et relance la réponse.
    func editMessage(_ id: UUID, newText: String) {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating, !text.isEmpty, let selectedID, let index = index(of: selectedID),
              let position = conversations[index].messages.firstIndex(where: { $0.id == id }),
              conversations[index].messages[position].role == .user
        else { return }
        conversations[index].messages[position].content = text
        conversations[index].messages[position].memoryUpdated = false
        let removed = conversations[index].messages[(position + 1)...]
        for message in removed {
            for name in message.images { try? FileManager.default.removeItem(at: AttachmentStore.shared.url(for: name)) }
        }
        conversations[index].messages.removeSubrange((position + 1)...)
        conversations[index].memoryProcessedCount = min(conversations[index].memoryProcessedCount, position)
        conversations[index].updatedAt = Date()
        editingMessageID = nil
        handleMemoryCommand(in: text, conversationID: selectedID, messageID: id)
        save()
        generate(in: selectedID)
    }

    // MARK: - Export

    func exportConversation(_ id: UUID) {
        guard let conversation = conversation(id) else { return }
        let panel = NSSavePanel()
        panel.title = "Exporter la conversation"
        panel.nameFieldStringValue = ConversationExporter.fileName(for: conversation)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConversationExporter.markdown(for: conversation).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            attachmentError = "Export impossible : \(error.localizedDescription)"
        }
    }
}
