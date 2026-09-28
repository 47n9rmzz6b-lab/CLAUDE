import SwiftUI

/// Zone de saisie : Entrée envoie, Maj+Entrée (ou Option+Entrée) passe à la ligne.
struct ComposerView: View {
    @Environment(ChatStore.self) private var store

    @Binding var text: String
    /// Prend le focus clavier même si la liste des conversations l’avait.
    let forceFocus: Bool
    /// La réponse en cours de génération appartient à cette conversation (bouton « Arrêter »).
    let isGeneratingHere: Bool
    let onSend: (String) -> Void

    @State private var editorHeight: CGFloat = 20

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedText.isEmpty && !store.isGenerating && !store.currentModel.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Écrivez votre message…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                GrowingTextView(text: $text, height: $editorHeight, forceFocus: forceFocus, onSubmit: submit)
                    .frame(height: editorHeight)
            }

            HStack(spacing: 10) {
                ModelPicker()
                Spacer()
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

    private func submit() {
        guard canSend else { return }
        let message = trimmedText
        text = ""
        onSend(message)
    }
}

/// Menu de choix du modèle, placé sous la zone de saisie comme dans l’application Claude.
struct ModelPicker: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        Menu {
            if store.models.isEmpty {
                Text("Aucun modèle disponible")
            } else {
                Picker("Modèle", selection: Binding(get: { store.currentModel }, set: { store.selectModel($0) })) {
                    ForEach(store.models) { model in
                        Text(model.name).tag(model.name)
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
}
