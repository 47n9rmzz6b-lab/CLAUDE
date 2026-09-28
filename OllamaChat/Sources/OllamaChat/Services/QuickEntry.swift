import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Raccourci global qui ouvre le panneau de saisie rapide.
enum QuickEntryShortcut: String, CaseIterable, Identifiable {
    case optionSpace = "option-space"
    case controlOptionSpace = "control-option-space"
    case shiftCommandSpace = "shift-command-space"
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionSpace: return "⌥ Espace"
        case .controlOptionSpace: return "⌃⌥ Espace"
        case .shiftCommandSpace: return "⇧⌘ Espace"
        case .off: return "Désactivé"
        }
    }

    var carbonModifiers: UInt32? {
        switch self {
        case .optionSpace: return UInt32(optionKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .shiftCommandSpace: return UInt32(shiftKey | cmdKey)
        case .off: return nil
        }
    }

    static var current: QuickEntryShortcut {
        QuickEntryShortcut(rawValue: UserDefaults.standard.string(forKey: SettingsKey.quickEntryShortcut) ?? "") ?? .optionSpace
    }
}

/// Raccourci clavier global (API Carbon : aucune autorisation d’accessibilité n’est nécessaire).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onTrigger: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Renvoie `false` si le raccourci est déjà pris par une autre application.
    @discardableResult
    func register(_ shortcut: QuickEntryShortcut) -> Bool {
        unregister()
        guard let modifiers = shortcut.carbonModifiers else { return true }
        installHandlerIfNeeded()
        let identifier = EventHotKeyID(signature: OSType(0x4F4C_4348), id: 1) // « OLCH »
        let status = RegisterEventHotKey(UInt32(kVK_Space), modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            Task { @MainActor in
                HotKeyCenter.shared.onTrigger?()
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }
}

/// Panneau flottant de saisie rapide, à la manière de Spotlight.
@MainActor
final class QuickEntryController {
    static let shared = QuickEntryController()

    weak var store: ChatStore?
    private var panel: QuickEntryPanel?

    func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard let store else { return }
        let panel = self.panel ?? makePanel(store: store)
        self.panel = panel
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + frame.height * 0.68)
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(store: ChatStore) -> QuickEntryPanel {
        let panel = QuickEntryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 76),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        let view = QuickEntryView(
            onSubmit: { [weak self, weak store] text in
                self?.close()
                store?.quickAsk(text)
                Self.showMainWindow()
            },
            onCancel: { [weak self] in self?.close() }
        )
        .environment(store)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }

    static func showMainWindow() {
        NSApp.activate()
        let window = NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }
        window?.makeKeyAndOrderFront(nil)
    }
}

final class QuickEntryPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    // Un clic ailleurs referme le panneau.
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

private struct QuickEntryView: View {
    @Environment(ChatStore.self) private var store
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.accent)
            TextField("Demandez à \(store.draftModel.isEmpty ? "Ollama" : store.draftModel)…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Pendant une réponse, la question reste dans le champ : Entrée la renverra.
                    guard !value.isEmpty, !store.isGenerating else { return }
                    text = ""
                    onSubmit(value)
                }
                .onExitCommand(perform: onCancel)
        }
        .padding(.horizontal, 20)
        .frame(width: 640, height: 76)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.composerBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.border)
        )
        .onAppear { focused = true }
    }
}
