import AppKit
import SwiftUI

@main
struct OllamaChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: ChatStore

    init() {
        AppDefaults.register()
        _store = State(initialValue: ChatStore())
    }

    var body: some Scene {
        Window("Ollama Chat", id: "main") {
            ContentView()
                .environment(store)
                .tint(Theme.accent)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(Self.defaultWindowSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle conversation") { store.newConversation() }
                    .keyboardShortcut("n")
            }
            CommandMenu("Conversation") {
                Button("Arrêter la génération") { store.stopGeneration() }
                    .keyboardShortcut(".")
                    .disabled(!store.isGenerating)
                Button("Régénérer la dernière réponse") { store.regenerate() }
                    .keyboardShortcut("r")
                    .disabled(!store.canRegenerate)
                Divider()
                Button("Gérer les modèles…") { store.showModelManager = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Actualiser la liste des modèles") {
                    Task { await store.refreshModels() }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .tint(Theme.accent)
        }
    }

    /// Taille initiale de la fenêtre, réduite sur les petits écrans pour qu’elle y tienne entière :
    /// une fenêtre plus grande que l’écran, redimensionnée par le système, s’affiche mal au lancement.
    private static var defaultWindowSize: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(
            width: min(1100, (visible.width * 0.92).rounded()),
            height: min(760, (visible.height * 0.92).rounded())
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SMOKE-DEBUG
        if UserDefaults.standard.bool(forKey: "debugDumpViews") {
            Task { @MainActor in
                for (label, wait) in [("t=0.5", 0.5), ("t=2", 1.5), ("t=6", 4.0)] {
                    try? await Task.sleep(for: .seconds(wait))
                    Self.dumpViews(label)
                }
            }
        }
        if UserDefaults.standard.bool(forKey: "debugNoActivate") { return } // SMOKE-DEBUG
        // Lancée avec « swift run », l’app n’est pas dans un bundle .app : on la déclare
        // comme application normale pour qu’elle ait une icône dans le Dock et le focus clavier.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    // SMOKE-DEBUG
    static func dumpViews(_ label: String) {
        var out = "==== \(label)\n"
        var lines = 0
        func dump(_ view: NSView, _ depth: Int) {
            guard depth < 16, lines < 500 else { return }
            lines += 1
            var line = String(repeating: "  ", count: depth) + "\(type(of: view)) \(view.frame)"
            if view.isHidden { line += " HIDDEN" }
            if let clip = view as? NSClipView { line += " bounds=\(clip.bounds)" }
            if let scroll = view as? NSScrollView { line += " insets=\(scroll.contentInsets) doc=\(scroll.documentView?.frame ?? .zero)" }
            out += line + "\n"
            for sub in view.subviews { dump(sub, depth + 1) }
        }
        for window in NSApp.windows where window.isVisible {
            out += "window \(type(of: window)) frame=\(window.frame) contentLayout=\(window.contentLayoutRect)\n"
            if let root = window.contentView { dump(root, 0) }
        }
        let url = URL(fileURLWithPath: "/tmp/ollamachat-views.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(out.utf8))
            try? handle.close()
        } else {
            try? out.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
