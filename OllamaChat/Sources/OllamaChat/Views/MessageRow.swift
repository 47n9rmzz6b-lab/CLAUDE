import SwiftUI

/// Un message du fil. `Equatable` : seules les lignes qui changent (en pratique, la réponse
/// en cours de génération) sont redessinées à chaque nouveau fragment reçu.
struct MessageRow: View, Equatable {
    let message: ChatMessage
    let isLast: Bool
    let isStreaming: Bool
    let serif: Bool

    var body: some View {
        if message.role == .user {
            UserMessageView(text: message.content)
        } else {
            AssistantMessageView(message: message, isLast: isLast, isStreaming: isStreaming, serif: serif)
        }
    }
}

private struct UserMessageView: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(text)
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
                    Button("Copier") { Pasteboard.copy(text) }
                }
        }
    }
}

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
            if !thinking.isEmpty {
                ThinkingView(text: thinking, inProgress: isStreaming && answer.isEmpty, isExpanded: $showThinking)
            }
            if !answer.isEmpty {
                MarkdownView(text: answer, serif: serif)
            }
            if isStreaming {
                StreamingIndicator()
            }
            if let error = message.errorText {
                ErrorView(message: error, onRetry: isLast ? retry : nil)
            } else if !isStreaming && answer.isEmpty && thinking.isEmpty {
                Text("Réponse interrompue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

private struct ThinkingView: View {
    let text: String
    let inProgress: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text(inProgress ? "Réflexion en cours…" : "Réflexion")
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
