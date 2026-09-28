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
        .onChange(of: store.selectedID) {
            UserDefaults.standard.set(store.selectedID?.uuidString, forKey: SettingsKey.lastConversationID)
        }
    }
}
