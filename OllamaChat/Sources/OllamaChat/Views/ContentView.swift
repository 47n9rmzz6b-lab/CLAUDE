import SwiftUI

struct ContentView: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 380)
        } detail: {
            ChatView()
                .id(store.selectedID)
        }
        .sheet(isPresented: $store.showModelManager) {
            ModelManagerView()
                .environment(store)
        }
        .task {
            await store.monitorConnection()
        }
        .onAppear {
            // Saisie rapide : raccourci global et panneau flottant.
            QuickEntryController.shared.store = store
            HotKeyCenter.shared.onTrigger = { QuickEntryController.shared.toggle() }
            HotKeyCenter.shared.register(QuickEntryShortcut.current)
        }
        .onChange(of: store.selectedID) { previous, current in
            UserDefaults.standard.set(current?.uuidString, forKey: SettingsKey.lastConversationID)
            store.editingMessageID = nil
            store.conversationDidChange(from: previous)
        }
    }
}
