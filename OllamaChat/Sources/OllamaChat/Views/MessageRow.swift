import AppKit
import SwiftUI

/// Un message du fil. `Equatable` : seules les lignes qui changent (en pratique, la réponse
/// en cours de génération) sont redessinées à chaque nouveau fragment reçu.
struct MessageRow: View, Equatable {
    let message: ChatMessage
    let isLast: Bool
    let isStreaming: Bool
    let isEditing: Bool
    let serif: Bool

    var body: some View {
        if message.role == .user {
            if message.kind == .verification {
                VerificationRequestView(memoryUpdated: message.memoryUpdated)
            } else if isEditing {
                MessageEditor(message: message)
            } else {
                UserMessageView(message: message)
            }
        } else {
            AssistantMessageView(message: message, isLast: isLast, isStreaming: isStreaming, serif: serif)
        }
    }
}

// MARK: - Messages de l’utilisateur

private struct UserMessageView: View {
    @Environment(ChatStore.self) private var store
    let message: ChatMessage
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !message.images.isEmpty {
                HStack(spacing: 6) {
                    Spacer(minLength: 80)
                    ForEach(message.images, id: \.self) { name in
                        ImageThumbnail(name: name)
                    }
                }
            }
            if !message.content.isEmpty {
                HStack(alignment: .bottom, spacing: 6) {
                    Spacer(minLength: 80)
                    if isHovering && !store.isGenerating {
                        Button {
                            store.editingMessageID = message.id
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help("Modifier ce message et relancer la réponse")
                    }
                    Text(message.content)
                        .font(.system(size: 14.5))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.userBubble)
                        )
                        .contextMenu {
                            Button("Copier") { Pasteboard.copy(message.content) }
                            Button("Modifier…") { store.editingMessageID = message.id }
                                .disabled(store.isGenerating)
                        }
                }
            }
            if message.memoryUpdated {
                MemoryChip()
            }
        }
        .onHover { isHovering = $0 }
    }
}

/// Modification d’un message déjà envoyé : la suite de la conversation est remplacée.
private struct MessageEditor: View {
    @Environment(ChatStore.self) private var store
    let message: ChatMessage
    @State private var text: String
    @FocusState private var focused: Bool

    init(message: ChatMessage) {
        self.message = message
        _text = State(initialValue: message.content)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(size: 14.5))
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: 60, maxHeight: 220)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.composerBackground))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(0.6)))
            HStack {
                Text("Les réponses suivantes seront remplacées.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Annuler") { store.editingMessageID = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Envoyer") { store.editMessage(message.id, newText: text) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isGenerating)
            }
        }
        .padding(.leading, 80)
        .onAppear { focused = true }
    }
}

private struct VerificationRequestView: View {
    let memoryUpdated: Bool

    var body: some View {
        HStack {
            Spacer()
            Label("Vérification de la réponse demandée", systemImage: "checkmark.seal")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.userBubble))
        }
    }
}

private struct ImageThumbnail: View {
    let name: String

    var body: some View {
        Button {
            NSWorkspace.shared.open(AttachmentStore.shared.url(for: name))
        } label: {
            Group {
                if let image = AttachmentStore.shared.image(named: name) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.2)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Ouvrir l’image")
    }
}

private struct MemoryChip: View {
    var body: some View {
        Label("Mémoire mise à jour", systemImage: "brain.head.profile")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Des informations ont été retenues. Vous pouvez les consulter et les modifier dans Réglages › Mémoire.")
    }
}

// MARK: - Réponses

private struct AssistantMessageView: View {
    @Environment(ChatStore.self) private var store

    let message: ChatMessage
    let isLast: Bool
    let isStreaming: Bool
    let serif: Bool

    @State private var isHovering = false
    @State private var showThinking = false
    @State private var copied = false

    var body: some View {
        let parsed = ThinkingParser.split(message.content)
        let thinking = [message.thinking, parsed.thinking].filter { !$0.isEmpty }.joined(separator: "\n\n")
        let answer = parsed.answer

        VStack(alignment: .leading, spacing: 12) {
            if !message.steps.isEmpty {
                ToolStepsView(steps: message.steps)
            }
            if !thinking.isEmpty {
                ThinkingView(
                    text: thinking,
                    inProgress: isStreaming && answer.isEmpty,
                    seconds: message.thinkingSeconds,
                    isExpanded: $showThinking
                )
            }
            if !answer.isEmpty {
                MarkdownView(text: answer, serif: serif)
            }
            if isStreaming {
                StreamingIndicator()
            }
            if !message.sources.isEmpty && !isStreaming {
                SourcesView(sources: message.sources)
            }
            if let error = message.errorText {
                ErrorView(message: error, onRetry: isLast ? retry : nil)
            } else if !isStreaming && answer.isEmpty && thinking.isEmpty {
                Text("Réponse interrompue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if message.memoryUpdated {
                MemoryChip()
            }
            if !isStreaming && !answer.isEmpty {
                actionBar(answer: answer)
                    .opacity(isHovering || isLast ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private func retry() {
        store.regenerate()
    }

    private func actionBar(answer: String) -> some View {
        HStack(spacing: 2) {
            Button {
                Pasteboard.copy(answer)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 26, height: 22)
            }
            .help("Copier la réponse")

            if isLast {
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 26, height: 22)
                }
                .help("Régénérer la réponse (⌘R)")
                .disabled(store.isGenerating)

                Button {
                    store.verifyLastAnswer()
                } label: {
                    Image(systemName: "checkmark.seal")
                        .frame(width: 26, height: 22)
                }
                .help("Demander au modèle de vérifier cette réponse (⇧⌘V)")
                .disabled(store.isGenerating)
            }

            if let footer = footerText {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 6)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    private var footerText: String? {
        var parts: [String] = []
        if let model = message.model, !model.isEmpty {
            parts.append(model)
        }
        if let speed = message.stats?.tokensPerSecond {
            parts.append("\(speed.formatted(.number.precision(.fractionLength(1)))) jetons/s")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Étapes de préparation : recherches, pages lues, documents consultés.
private struct ToolStepsView: View {
    let steps: [ToolStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(steps) { step in
                HStack(spacing: 8) {
                    Image(systemName: icon(for: step))
                        .foregroundStyle(step.error == nil ? Theme.accent : Color.orange)
                        .frame(width: 16)
                    Text(title(for: step))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if step.isRunning {
                        ProgressView().controlSize(.mini)
                    } else if let count = step.resultCount, step.kind == .search {
                        Text("\(count) résultat\(count > 1 ? "s" : "")")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if let error = step.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.leading, 24)
                }
            }
        }
    }

    private func icon(for step: ToolStep) -> String {
        switch step.kind {
        case .search: return "magnifyingglass"
        case .fetch: return "globe"
        case .documents: return "doc.text.magnifyingglass"
        }
    }

    private func title(for step: ToolStep) -> String {
        switch step.kind {
        case .search: return "Recherche : « \(step.detail) »"
        case .fetch: return "Lecture de \(step.detail)"
        case .documents: return step.detail
        }
    }
}

/// Sources citées : liens web numérotés et passages de documents.
private struct SourcesView: View {
    let sources: [Source]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(sources) { source in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(source.tag)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 22)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    if let address = source.url, let url = URL(string: address) {
                        Link(destination: url) {
                            Text(source.title).lineLimit(1)
                        }
                        .font(.callout)
                        if let detail = source.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(source.title)
                            .font(.callout)
                            .lineLimit(1)
                        if let detail = source.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
    }
}

private struct ThinkingView: View {
    let text: String
    let inProgress: Bool
    let seconds: Double?
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text(label)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    if inProgress {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 2)
                    }
            }
        }
    }

    private var label: String {
        if inProgress { return "Réflexion en cours…" }
        guard let seconds, seconds >= 1 else { return "Réflexion" }
        if seconds < 60 { return "A réfléchi \(Int(seconds.rounded())) s" }
        let minutes = Int(seconds) / 60
        return "A réfléchi \(minutes) min \(Int(seconds) % 60) s"
    }
}

private struct StreamingIndicator: View {
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.accent)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityLabel("Génération en cours")
    }
}

private struct ErrorView: View {
    let message: String
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let onRetry {
                Button("Réessayer", action: onRetry)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }
}
