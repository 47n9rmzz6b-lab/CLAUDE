import AppKit
import SwiftUI

/// Champ de texte multiligne (NSTextView) qui grandit avec son contenu jusqu’à `maxHeight`.
/// Entrée appelle `onSubmit` ; Maj+Entrée ou Option+Entrée insère un retour à la ligne.
/// La saisie avec une méthode d’entrée (accents composés, japonais…) n’est pas interrompue :
/// tant qu’une composition est en cours, Entrée la valide sans envoyer le message.
struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var forceFocus = false
    var font: NSFont = .systemFont(ofSize: 14)
    var minHeight: CGFloat = 20
    var maxHeight: CGFloat = 220
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerTextView(usingTextLayoutManager: false)
        textView.forceFocus = forceFocus
        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        let scrollView = ResizeAwareScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)

        let coordinator = context.coordinator
        coordinator.textView = textView
        // La largeur change avec la fenêtre : le texte se réagence et la hauteur doit suivre.
        scrollView.onWidthChange = { [weak coordinator] in
            coordinator?.recalculateHeight()
        }
        coordinator.recalculateHeight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.recalculateHeight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        weak var textView: NSTextView?

        init(parent: GrowingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }

        func recalculateHeight() {
            guard let textView,
                  let container = textView.textContainer,
                  let layoutManager = textView.layoutManager
            else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
            let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? parent.font)
            let target = min(max(used, lineHeight, parent.minHeight), parent.maxHeight).rounded(.up)
            guard abs(target - parent.height) > 0.5 else { return }
            // Différé : la hauteur est un état SwiftUI qu’on ne modifie pas pendant une mise à jour de vue.
            Task { @MainActor [weak self] in
                self?.parent.height = target
            }
        }
    }
}

private final class ComposerTextView: NSTextView {
    var forceFocus = false
    private var didAttemptFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !didAttemptFocus else { return }
        didAttemptFocus = true
        // Après un clic sur une conversation, on peut écrire tout de suite ; mais on laisse le focus
        // à la liste des conversations quand on la parcourt au clavier (flèches).
        let browsingListWithKeyboard = window.firstResponder is NSTableView && NSApp.currentEvent?.type == .keyDown
        if forceFocus || !browsingListWithKeyboard {
            window.makeFirstResponder(self)
        }
    }
}

private final class ResizeAwareScrollView: NSScrollView {
    var onWidthChange: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            onWidthChange?()
        }
    }
}
