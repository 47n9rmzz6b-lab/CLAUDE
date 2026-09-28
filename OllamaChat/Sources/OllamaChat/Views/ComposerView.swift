import SwiftUI

/// Zone de saisie : Entrée envoie, Maj+Entrée (ou Option+Entrée) passe à la ligne,
/// ↑ dans une zone vide modifie le dernier message, ⌘V colle aussi les images.
struct ComposerView: View {
    @Environment(ChatStore.self) private var store

    @Binding var text: String
    /// Prend le focus clavier à l’affichage.
    let takesFocus: Bool
    /// La réponse en cours de génération appartient à cette conversation (bouton « Arrêter »).
    let isGeneratingHere: Bool
    let onSend: (String) -> Void

    @State private var editorHeight: CGFloat = 20

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        (!trimmedText.isEmpty || !store.pendingImages.isEmpty)
            && !store.isGenerating
            && !store.currentModel.isEmpty
            && !store.imagesNeedVisionModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AttachmentStrip()
            notices

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(store.dictation.isActive ? "Parlez, le texte s’écrit ici…" : "Écrivez votre message…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                GrowingTextView(
                    text: $text,
                    height: $editorHeight,
                    takesFocus: takesFocus,
                    onSubmit: submit,
                    onPasteImage: { store.attachImage(data: $0) },
                    onEditLast: { store.editingMessageID = store.lastEditableMessageID }
                )
                .frame(height: editorHeight)
            }

            HStack(spacing: 6) {
                AttachButton()
                WebSearchToggle()
                ThinkingControl()
                ProfileMenu()
                Spacer(minLength: 8)
                ContextGauge(draft: text)
                ModelPicker()
                DictationButton(text: $text)
                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.composerBackground)
                .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.border)
        )
    }

    @ViewBuilder
    private var notices: some View {
        if store.imagesNeedVisionModel {
            NoticeText(
                icon: "eye.slash",
                text: "« \(store.currentModel) » ne voit pas les images. Choisissez un modèle de vision (gemma3, qwen2.5vl, llava…)."
            )
        }
        if let error = store.attachmentError {
            NoticeText(icon: "exclamationmark.triangle", text: error) { store.attachmentError = nil }
        }
        if let error = store.dictation.errorMessage {
            NoticeText(icon: "mic.slash", text: error) { store.dictation.dismissError() }
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if isGeneratingHere {
            Button {
                store.stopGeneration()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .help("Arrêter la génération (⌘.)")
        } else {
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(canSend ? Theme.accent : Color.secondary.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Envoyer (Entrée)")
        }
    }

    private func submit() {
        guard canSend else { return }
        if store.dictation.isActive { store.dictation.stop() }
        let message = trimmedText
        text = ""
        onSend(message)
    }
}

/// Petit avertissement affiché au-dessus du texte.
struct NoticeText: View {
    let icon: String
    let text: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
