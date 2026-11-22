import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared bits

struct ArtworkView: View {
    let track: Track
    var size: CGFloat = 48

    var body: some View {
        if let url = LibraryFiles.artworkURL(for: track), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size, height: size).clipped()
        } else {
            RoundedRectangle(cornerRadius: Theme.radiusS)
                .fill(Theme.surfaceRaised)
                .frame(width: size, height: size)
                .overlay(Image(systemName: "music.note").foregroundStyle(Theme.textMuted))
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String = "music.note"

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

struct TrackRow: View {
    @EnvironmentObject private var player: PlayerEngine
    let track: Track
    var onAddToPlaylist: ((Track) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).lineLimit(1)
                    .foregroundStyle(isCurrent ? Theme.accent : Theme.textPrimary)
                Text("\(track.artistDisplay) · \(track.albumDisplay)")
                    .font(.caption).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent)
            }
            if track.isFavorite {
                Image(systemName: "heart.fill").foregroundStyle(Theme.accent).font(.caption)
            }
            Text(track.durationSec.timeString).font(.caption).foregroundStyle(Theme.textMuted)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { onAddToPlaylist?(track) } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
            Button { track.isFavorite.toggle() } label: {
                Label(track.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: track.isFavorite ? "heart.slash" : "heart")
            }
        }
    }

    private var isCurrent: Bool { player.currentTrack?.id == track.id }
}

/// A tappable list of tracks that starts playback with the whole list as the queue.
struct TrackList: View {
    @EnvironmentObject private var player: PlayerEngine
    let tracks: [Track]
    @State private var playlistCandidate: Track?

    var body: some View {
        List(tracks) { track in
            TrackRow(track: track, onAddToPlaylist: { playlistCandidate = $0 })
                .listRowBackground(Color.clear)
                .onTapGesture {
                    if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                        player.play(tracks: tracks, startAt: index)
                    }
                }
        }
        .listStyle(.plain)
        .sheet(item: $playlistCandidate) { track in
            AddToPlaylistView(track: track)
        }
    }
}

extension Track: Identifiable {}
extension Playlist: Identifiable {}
extension FolderBookmark: Identifiable {}

// MARK: - S01/S02 Onboarding & sources

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var library: LibraryService
    @State private var showFolderPicker = false
    @State private var showFilePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bring your music in")
                .font(.headline)
            Text("Sonara plays files you own. Pick a folder on this device, import files, or use songs already in your Music library. Everything stays on your phone.")
                .font(.footnote).foregroundStyle(Theme.textMuted)

            sourceButton(title: "Choose a Folder", detail: "The folder stays where it is; Sonara remembers it.",
                         systemImage: "folder") { showFolderPicker = true }
            sourceButton(title: "Import Files", detail: "Copies songs into Sonara so they are always available.",
                         systemImage: "square.and.arrow.down") { showFilePicker = true }
            sourceButton(title: "Use Music Library", detail: "Songs synced to this iPhone (protected or cloud-only songs cannot be played).",
                         systemImage: "music.note.house") {
                Task { await library.syncMediaLibrary(context: modelContext) }
            }

            if library.isScanning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: library.scanProgress)
                    Text(library.scanMessage ?? "Scanning…").font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusL))
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await library.addFolder(url, context: modelContext) }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await library.importFiles(urls, context: modelContext) }
            }
        }
    }

    private func sourceButton(title: String, detail: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(Theme.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(detail).font(.caption).foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

// MARK: - S03 Home

struct HomeView: View {
    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if tracks.isEmpty {
                        SourcesView()
                    } else {
                        smartCards
                        if !recentlyAdded.isEmpty {
                            sectionHeader("Recently Added")
                            TrackListPreview(tracks: Array(recentlyAdded.prefix(5)))
                        }
                        if !mostPlayed.isEmpty {
                            sectionHeader("Most Played")
                            TrackListPreview(tracks: Array(mostPlayed.prefix(5)))
                        }
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle("Sonara")
        }
    }

    private var favorites: [Track] { tracks.filter(\.isFavorite) }
    private var mostPlayed: [Track] { tracks.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount } }
    private var recentlyAdded: [Track] { tracks }

    private var smartCards: some View {
        HStack(spacing: 12) {
            NavigationLink { SmartListView(kind: .favorites) } label: {
                smartCard(title: "Favorites", count: favorites.count, systemImage: "heart.fill")
            }
            NavigationLink { SmartListView(kind: .mostPlayed) } label: {
                smartCard(title: "Most Played", count: mostPlayed.count, systemImage: "chart.bar.fill")
            }
            NavigationLink { SmartListView(kind: .recentlyAdded) } label: {
                smartCard(title: "Recently Added", count: recentlyAdded.count, systemImage: "clock.fill")
            }
        }
    }

    private func smartCard(title: String, count: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(Theme.accent)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
            Text("\(count) songs").font(.caption2).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusL))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
    }
}

/// Compact, non-List preview used inside Home's ScrollView.
struct TrackListPreview: View {
    @EnvironmentObject private var player: PlayerEngine
    let tracks: [Track]
    @State private var playlistCandidate: Track?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(tracks) { track in
                TrackRow(track: track, onAddToPlaylist: { playlistCandidate = $0 })
                    .padding(.vertical, 4)
                    .onTapGesture {
                        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                            player.play(tracks: tracks, startAt: index)
                        }
                    }
                Divider().overlay(Theme.border)
            }
        }
        .sheet(item: $playlistCandidate) { track in AddToPlaylistView(track: track) }
    }
}

// MARK: - S04/S05/S06 Library

struct LibraryView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @State private var section = 0

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Section", selection: $section) {
                    Text("Songs").tag(0)
                    Text("Albums").tag(1)
                    Text("Folders").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if tracks.isEmpty {
                    EmptyStateView(title: "No songs yet", message: "Add a folder or import files from the Home tab.")
                } else {
                    switch section {
                    case 0: TrackList(tracks: tracks)
                    case 1: AlbumsView(tracks: tracks)
                    default: FoldersView(tracks: tracks)
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("Library")
        }
    }
}

struct AlbumGroup: Identifiable {
    var id: String { title + "|" + artist }
    let title: String
    let artist: String
    let tracks: [Track]
}

struct AlbumsView: View {
    let tracks: [Track]

    var groups: [AlbumGroup] {
        Dictionary(grouping: tracks) { "\($0.albumDisplay)|\($0.albumArtist ?? $0.artistDisplay)" }
            .map { key, value in
                AlbumGroup(title: value[0].albumDisplay,
                           artist: value[0].albumArtist ?? value[0].artistDisplay,
                           tracks: value.sorted { $0.title < $1.title })
            }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        List(groups) { group in
            NavigationLink {
                VStack {
                    Text("\(group.tracks.count) songs").font(.caption).foregroundStyle(Theme.textMuted)
                    TrackList(tracks: group.tracks)
                }
                .navigationTitle(group.title)
            } label: {
                HStack(spacing: 12) {
                    if let first = group.tracks.first {
                        ArtworkView(track: first).clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title).lineLimit(1)
                        Text(group.artist).font(.caption).foregroundStyle(Theme.textMuted).lineLimit(1)
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
    }
}

struct FoldersView: View {
    let tracks: [Track]
    @Query private var bookmarks: [FolderBookmark]

    var body: some View {
        List {
            if !bookmarks.isEmpty {
                Section("Folders you added") {
                    ForEach(bookmarks) { bookmark in
                        let folderTracks = tracks.filter { $0.folderBookmarkID == bookmark.id }
                        NavigationLink {
                            TrackList(tracks: folderTracks)
                                .navigationTitle(bookmark.displayName)
                        } label: {
                            Label("\(bookmark.displayName) (\(folderTracks.count))", systemImage: "folder")
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            let imported = tracks.filter { $0.source == .imported }
            if !imported.isEmpty {
                Section("Imported into Sonara") {
                    NavigationLink {
                        TrackList(tracks: imported).navigationTitle("Imported")
                    } label: {
                        Label("Imported (\(imported.count))", systemImage: "square.and.arrow.down")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            let media = tracks.filter { $0.source == .mediaLibrary }
            if !media.isEmpty {
                Section("Music library") {
                    NavigationLink {
                        TrackList(tracks: media).navigationTitle("Music Library")
                    } label: {
                        Label("Music Library (\(media.count))", systemImage: "music.note.house")
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - S07 Search

struct SearchView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @State private var query = ""

    var results: [Track] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return tracks.filter {
            $0.title.lowercased().contains(q)
                || ($0.artist?.lowercased().contains(q) ?? false)
                || ($0.album?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    EmptyStateView(title: "Search your library", message: "Titles, artists and albums — all on this device.", systemImage: "magnifyingglass")
                } else if results.isEmpty {
                    EmptyStateView(title: "No matches", message: "Nothing in your library matches “\(query)”.", systemImage: "magnifyingglass")
                } else {
                    TrackList(tracks: results)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Songs, artists, albums")
        }
    }
}
