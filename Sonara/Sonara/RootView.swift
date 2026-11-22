import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var library: LibraryService
    @EnvironmentObject private var eqStore: EQStore
    @State private var showNowPlaying = false
    @State private var wired = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "music.note.list") }
            PlaylistsView()
                .tabItem { Label("Playlists", systemImage: "list.bullet.rectangle") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .overlay(alignment: .bottom) {
            if player.currentTrack != nil {
                MiniPlayerBar { showNowPlaying = true }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 54)
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { player.lastError != nil || library.lastError != nil },
            set: { if !$0 { player.lastError = nil; library.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.lastError ?? library.lastError ?? "")
        }
        .onAppear { wireServices() }
        .onChange(of: eqStore.settings) { _, newValue in player.applyEQ(newValue) }
    }

    private func wireServices() {
        guard !wired else { return }
        wired = true
        let context = modelContext
        let libraryService = library
        player.resolveURL = { track in libraryService.url(for: track, context: context) }
        player.beginAccess = { track in libraryService.beginAccess(for: track, context: context) }
        player.onPlayCounted = { track in
            track.playCount += 1
            track.lastPlayedAt = Date()
            try? context.save()
        }
        player.applyEQ(eqStore.settings)
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerEngine
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let track = player.currentTrack {
                ArtworkView(track: track, size: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(track.artistDisplay).font(.caption).foregroundStyle(Theme.textMuted).lineLimit(1)
                }
                Spacer()
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .accessibilityLabel("Next track")
            }
        }
        .padding(10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusL))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
