import AppKit
import SwiftUI

/// Fil de la conversation. Pendant la génération, la vue suit la fin de la réponse, sauf si
/// l’utilisateur remonte dans l’historique ; un bouton permet alors de revenir en bas.
struct MessageListView: View {
    let conversation: Conversation
    let streamingMessageID: UUID?
    let serif: Bool

    /// Suivre la fin du fil. Seul un défilement vers le haut fait par l’utilisateur l’interrompt :
    /// un bloc qui grandit d’un coup (tableau, code) ne doit pas faire perdre le fil.
    @State private var followsBottom = true
    @State private var isAtBottom = true
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollMonitor: Any?

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
                isAtBottom = bottom <= viewportHeight + 40
                if isAtBottom { followsBottom = true }
            }
            .onAppear {
                startWatchingUserScroll()
                scrollToBottom(proxy, settling: true)
            }
            .onDisappear {
                if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
                scrollMonitor = nil
            }
            .onChange(of: conversation.messages.count) {
                followsBottom = true
                scrollToBottom(proxy, animated: true, settling: true)
            }
            .onChange(of: viewportHeight) {
                // Bandeau qui apparaît, fenêtre redimensionnée : on garde la fin du fil en vue.
                if followsBottom { scrollToBottom(proxy) }
            }
            .onChange(of: lastMessageLength) {
                if followsBottom { scrollToBottom(proxy) }
            }
            .overlay(alignment: .bottom) {
                if !isAtBottom && !followsBottom {
                    Button {
                        followsBottom = true
                        scrollToBottom(proxy, animated: true)
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

    /// Défile jusqu’en bas une fois la mise en page faite : les lignes qui viennent
    /// d’apparaître ou de grandir ont alors leur hauteur définitive. `settling` répète
    /// l’opération pendant que la mise en page se stabilise (ouverture, nouveau message).
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = false, settling: Bool = false) {
        Task { @MainActor in
            for delay in settling ? [16, 150, 400] : [16] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard followsBottom else { return }
                if animated {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
    }

    private func startWatchingUserScroll() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Défilement vers le début du fil (molette, trackpad) : on arrête de suivre la réponse.
            if event.scrollingDeltaY > 0 {
                followsBottom = false
            }
            return event
        }
    }
}

private struct BottomOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
