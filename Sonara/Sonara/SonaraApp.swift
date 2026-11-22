import SwiftData
import SwiftUI

@main
struct SonaraApp: App {
    @StateObject private var player = PlayerEngine()
    @StateObject private var library = LibraryService()
    @StateObject private var eqStore = EQStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(eqStore)
                .tint(Theme.accent)
        }
        .modelContainer(for: [Track.self, Playlist.self, PlaylistItem.self, FolderBookmark.self])
    }
}
