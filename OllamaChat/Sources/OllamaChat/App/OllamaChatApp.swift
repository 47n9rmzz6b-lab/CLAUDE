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
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(Self.defaultWindowSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle conversation") { store.newConversation() }
                    .keyboardShortcut("n")
                Button("Joindre des fichiers…") { store.chooseAttachments() }
                    .keyboardShortcut("o")
                Divider()
                Button("Exporter la conversation…") {
                    if let id = store.selectedID { store.exportConversation(id) }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(store.selectedID == nil)
            }
            CommandMenu("Conversation") {
                Button("Arrêter la génération") { store.stopGeneration() }
                    .keyboardShortcut(".")
                    .disabled(!store.isGenerating)
                Button("Régénérer la dernière réponse") { store.regenerate() }
                    .keyboardShortcut("r")
                    .disabled(!store.canRegenerate)
                Button("Vérifier la dernière réponse") { store.verifyLastAnswer() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
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

    /// Taille initiale de la fenêtre, réduite sur les petits écrans pour qu’elle y tienne entière.
    private static var defaultWindowSize: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(
            width: min(1100, (visible.width * 0.92).rounded()),
            height: min(760, (visible.height * 0.92).rounded())
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Reçoit les fichiers ouverts avec l’app (« Ouvrir avec », dépôt sur l’icône du Dock).
    weak var store: ChatStore? {
        didSet { flushPendingURLs() }
    }
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        flushPendingURLs()
    }

    private func flushPendingURLs() {
        guard let store, !pendingURLs.isEmpty else { return }
        store.attach(urls: pendingURLs)
        pendingURLs.removeAll()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lancée avec « swift run », l’app n’est pas dans un bundle .app : on la déclare
        // comme application normale pour qu’elle ait une icône dans le Dock et le focus clavier.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
