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
        .defaultSize(width: 1100, height: 760)
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
