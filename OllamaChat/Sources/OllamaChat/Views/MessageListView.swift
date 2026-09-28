import SwiftUI

/// Fil de la conversation. Pendant la génération, la vue suit la fin de la réponse,
/// sauf si l’utilisateur est remonté dans l’historique (un bouton permet alors de revenir en bas).
struct MessageListView: View {
    let conversation: Conversation
    let streamingMessageID: UUID?
    let serif: Bool

    @State private var isAtBottom = true
    @State private var viewportHeight: CGFloat = 0

    private let bottomID = "bottom"
    private let scrollSpace = "messageScroll"

    private var lastMessageLength: Int {
        guard let last = conversation.messages.last else { return 0 }
        return last.content.utf8.count + last.thinking.utf8.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(conversation.messages) { message in
                        MessageRow(
                            message: message,
                            isLast: message.id == conversation.messages.last?.id,
                            isStreaming: message.id == streamingMessageID,
                            serif: serif
                        )
                        .equatable()
                        .id(message.id)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)

                Color.clear
                    .frame(height: 1)
                    .id(bottomID)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: BottomOffsetKey.self,
                                value: geometry.frame(in: .named(scrollSpace)).maxY
                            )
                        }
                    )
            }
            .coordinateSpace(.named(scrollSpace))
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { viewportHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { viewportHeight = geometry.size.height }
                }
            )
            .onPreferenceChange(BottomOffsetKey.self) { bottom in
                guard viewportHeight > 0 else { return }
                isAtBottom = bottom <= viewportHeight + 80
            }
            .onAppear {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: conversation.messages.count) {
                isAtBottom = true
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .onChange(of: lastMessageLength) {
                if isAtBottom {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottom) {
                if !isAtBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.composerBackground))
                            .overlay(Circle().strokeBorder(Theme.border))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                    .help("Aller à la fin")
                }
            }
        }
    }
}

private struct BottomOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
