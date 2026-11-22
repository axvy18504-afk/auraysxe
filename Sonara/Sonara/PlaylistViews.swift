import SwiftData
import SwiftUI

// MARK: - S13 Smart lists

enum SmartListKind {
    case favorites, mostPlayed, recentlyAdded

    var title: String {
        switch self {
        case .favorites: return "Favorites"
        case .mostPlayed: return "Most Played"
        case .recentlyAdded: return "Recently Added"
        }
    }
}

struct SmartListView: View {
    let kind: SmartListKind
    @Query(sort: \Track.dateAdded, order: .reverse) private var byAdded: [Track]
    @Query private var all: [Track]

    var tracks: [Track] {
        switch kind {
        case .favorites: return all.filter(\.isFavorite).sorted { $0.title < $1.title }
        case .mostPlayed: return all.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }
        case .recentlyAdded: return byAdded
        }
    }

    var body: some View {
        Group {
            if tracks.isEmpty {
                EmptyStateView(title: "Nothing here yet",
                               message: kind == .favorites
                                   ? "Long-press a song or tap the heart while it plays."
                                   : "This list fills itself as you listen and add music.")
            } else {
                TrackList(tracks: tracks)
            }
        }
        .background(Theme.bg)
        .navigationTitle(kind.title)
    }
}

// MARK: - S11 Playlists

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @State private var showNewPlaylist = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    EmptyStateView(title: "No playlists yet",
                                   message: "Make one for the workout, the drive, the slow Sunday.",
                                   systemImage: "list.bullet.rectangle")
                } else {
                    List(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            HStack {
                                Image(systemName: "music.note.list").foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                    Text("\(playlist.items.count) songs")
                                        .font(.caption).foregroundStyle(Theme.textMuted)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewPlaylist = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New playlist")
                }
            }
            .alert("New Playlist", isPresented: $showNewPlaylist) {
                TextField("Name", text: $newName)
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    modelContext.insert(Playlist(name: name))
                    try? modelContext.save()
                    newName = ""
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
        }
    }
}

// MARK: - S12 Playlist detail

struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: PlayerEngine
    @Bindable var playlist: Playlist
    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        Group {
            if playlist.sortedItems.isEmpty {
                EmptyStateView(title: "This playlist is empty",
                               message: "Long-press any song in your library and choose Add to Playlist.")
            } else {
                List {
                    ForEach(playlist.sortedItems) { item in
                        if let track = item.track {
                            TrackRow(track: track)
                                .onTapGesture {
                                    let playable = playlist.sortedItems.compactMap(\.track)
                                    if let index = playable.firstIndex(where: { $0.id == track.id }) {
                                        player.play(tracks: playable, startAt: index)
                                    }
                                }
                        }
                    }
                    .onMove { from, to in
                        var items = playlist.sortedItems
                        items.move(fromOffsets: from, toOffset: to)
                        for (index, item) in items.enumerated() { item.position = index }
                        playlist.updatedAt = Date()
                        try? modelContext.save()
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            modelContext.delete(playlist.sortedItems[offset])
                        }
                        for (index, item) in playlist.sortedItems.enumerated() { item.position = index }
                        try? modelContext.save()
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .toolbar { EditButton() }
            }
        }
        .background(Theme.bg)
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button("Rename") { renameText = playlist.name; showRename = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Delete Playlist", role: .destructive) {
                    modelContext.delete(playlist)
                    try? modelContext.save()
                }
            }
        }
        .alert("Rename Playlist", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { playlist.name = name; playlist.updatedAt = Date(); try? modelContext.save() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

extension PlaylistItem: Identifiable {}

// MARK: - Add to playlist sheet

struct AddToPlaylistView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @State private var newName = ""
    let track: Track

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New playlist name", text: $newName)
                        Button("Create") {
                            let name = newName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            let playlist = Playlist(name: name)
                            modelContext.insert(playlist)
                            add(to: playlist)
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Your playlists") {
                    ForEach(playlists) { playlist in
                        Button {
                            add(to: playlist)
                        } label: {
                            HStack {
                                Text(playlist.name).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if playlist.items.contains(where: { $0.track?.id == track.id }) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func add(to playlist: Playlist) {
        guard !playlist.items.contains(where: { $0.track?.id == track.id }) else { dismiss(); return }
        let item = PlaylistItem(position: playlist.items.count, track: track)
        item.playlist = playlist
        modelContext.insert(item)
        playlist.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - S14 Settings

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var library: LibraryService
    @Query private var tracks: [Track]
    @Query private var bookmarks: [FolderBookmark]
    @State private var showSources = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    LabeledContent("Songs", value: "\(tracks.count)")
                    LabeledContent("Folders added", value: "\(bookmarks.count)")
                    Button("Add or manage sources") { showSources = true }
                    Button("Rescan folders") {
                        Task { await library.rescanAll(context: modelContext) }
                    }
                    if library.isScanning {
                        HStack { ProgressView(); Text(library.scanMessage ?? "Scanning…") }
                    }
                }
                Section("Playback") {
                    NavigationLink("Equalizer") { EqualizerView() }
                }
                Section("About") {
                    LabeledContent("App", value: "Sonara")
                    LabeledContent("Version", value: "1.0")
                    Text("An offline player for music you own. No account, no streaming, nothing leaves this device.")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showSources) {
                NavigationStack {
                    ScrollView { SourcesView().padding() }
                        .navigationTitle("Music Sources")
                }
            }
        }
    }
}
