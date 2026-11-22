import AVFoundation
import Foundation
import MediaPlayer
import SwiftData

/// Resolves a Track to a playable file URL, and owns scanning/importing.
/// Three iOS-legal sources (see architecture.md): imported copies in the sandbox,
/// a user-chosen folder via security-scoped bookmark, and the Music library (non-DRM).
enum LibraryFiles {
    static var musicDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var artworkDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func artworkURL(for track: Track) -> URL? {
        guard let name = track.artworkFile else { return nil }
        let url = artworkDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

struct SongMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var durationSec: Double = 0
    var artwork: Data?
}

enum MetadataReader {
    static func read(url: URL) async -> SongMetadata {
        let asset = AVURLAsset(url: url)
        var meta = SongMetadata()
        meta.durationSec = (try? await asset.load(.duration).seconds) ?? 0
        guard let items = try? await asset.load(.commonMetadata) else { return meta }
        for item in items {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle: meta.title = try? await item.load(.stringValue)
            case .commonKeyArtist: meta.artist = try? await item.load(.stringValue)
            case .commonKeyAlbumName: meta.album = try? await item.load(.stringValue)
            case .commonKeyCreator, .commonKeyAuthor: meta.albumArtist = try? await item.load(.stringValue)
            case .commonKeyType: meta.genre = try? await item.load(.stringValue)
            case .commonKeyArtwork: meta.artwork = try? await item.load(.dataValue)
            default: break
            }
        }
        return meta
    }
}

@MainActor
final class LibraryService: ObservableObject {
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var scanMessage: String?
    @Published var lastError: String?

    static let audioExtensions: Set<String> = ["mp3", "wav", "flac", "aac", "m4a", "aiff", "aif", "caf", "ogg"]

    // MARK: - URL resolution

    func url(for track: Track, context: ModelContext) -> URL? {
        switch track.source {
        case .imported:
            let url = LibraryFiles.musicDirectory.appendingPathComponent(track.filePath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .folderBookmark:
            guard let bookmarkID = track.folderBookmarkID,
                  let bookmark = fetchBookmark(id: bookmarkID, context: context),
                  let folder = resolve(bookmark: bookmark) else { return nil }
            return folder.appendingPathComponent(track.filePath)
        case .mediaLibrary:
            guard let pid = track.mediaPersistentID else { return nil }
            let query = MPMediaQuery.songs()
            query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid),
                                                               forProperty: MPMediaItemPropertyPersistentID))
            return query.items?.first?.assetURL
        }
    }

    /// Must be called before reading files under a bookmarked folder; returns a stop closure.
    func beginAccess(for track: Track, context: ModelContext) -> (() -> Void)? {
        guard track.source == .folderBookmark,
              let bookmarkID = track.folderBookmarkID,
              let bookmark = fetchBookmark(id: bookmarkID, context: context),
              let folder = resolve(bookmark: bookmark) else { return nil }
        guard folder.startAccessingSecurityScopedResource() else { return nil }
        return { folder.stopAccessingSecurityScopedResource() }
    }

    private func fetchBookmark(id: UUID, context: ModelContext) -> FolderBookmark? {
        let descriptor = FetchDescriptor<FolderBookmark>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func resolve(bookmark: FolderBookmark) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark.bookmarkData, bookmarkDataIsStale: &stale)
    }

    // MARK: - Folder source

    func addFolder(_ folderURL: URL, context: ModelContext) async {
        let scoped = folderURL.startAccessingSecurityScopedResource()
        defer { if scoped { folderURL.stopAccessingSecurityScopedResource() } }
        do {
            let data = try folderURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let bookmark = FolderBookmark(bookmarkData: data, displayName: folderURL.lastPathComponent)
            context.insert(bookmark)
            try context.save()
            await scanFolder(bookmark, context: context)
        } catch {
            lastError = "Could not add that folder: \(error.localizedDescription)"
        }
    }

    func rescanAll(context: ModelContext) async {
        let descriptor = FetchDescriptor<FolderBookmark>()
        for bookmark in (try? context.fetch(descriptor)) ?? [] {
            await scanFolder(bookmark, context: context)
        }
        await scanImported(context: context)
    }

    private func scanFolder(_ bookmark: FolderBookmark, context: ModelContext) async {
        guard let folder = resolve(bookmark: bookmark) else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        isScanning = true
        scanMessage = "Scanning \(bookmark.displayName)…"
        defer { isScanning = false; scanMessage = nil }

        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey],
                                                           options: [.skipsHiddenFiles]) {
            // allObjects, not async iteration: FileManager's iterator is
            // unavailable from async contexts (Swift 6 error).
            let all = (enumerator.allObjects as? [URL]) ?? []
            files = all.filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
        }
        for (index, file) in files.enumerated() {
            scanProgress = Double(index + 1) / Double(max(files.count, 1))
            let relative = file.path.replacingOccurrences(of: folder.path + "/", with: "")
            await upsert(fileURL: file, source: .folderBookmark, storedPath: relative,
                         bookmarkID: bookmark.id, context: context)
        }
        bookmark.lastScannedAt = Date()
        try? context.save()
    }

    // MARK: - Imported files

    func importFiles(_ urls: [URL], context: ModelContext) async {
        isScanning = true
        scanMessage = "Importing…"
        defer { isScanning = false; scanMessage = nil }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = "\(UUID().uuidString).\(url.pathExtension.lowercased())"
            let destination = LibraryFiles.musicDirectory.appendingPathComponent(name)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                await upsert(fileURL: destination, source: .imported, storedPath: name,
                             bookmarkID: nil, context: context)
            } catch {
                lastError = "Could not import \(url.lastPathComponent)."
            }
        }
        try? context.save()
    }

    private func scanImported(context: ModelContext) async {
        let files = (try? FileManager.default.contentsOfDirectory(at: LibraryFiles.musicDirectory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        for file in files where Self.audioExtensions.contains(file.pathExtension.lowercased()) {
            await upsert(fileURL: file, source: .imported, storedPath: file.lastPathComponent,
                         bookmarkID: nil, context: context)
        }
        try? context.save()
    }

    // MARK: - Music library (MediaPlayer, non-DRM only)

    func syncMediaLibrary(context: ModelContext) async {
        let status = await MPMediaLibrary.requestAuthorization()
        guard status == .authorized else {
            lastError = "Music library access was not granted."
            return
        }
        isScanning = true
        scanMessage = "Reading Music library…"
        defer { isScanning = false; scanMessage = nil }
        let items = MPMediaQuery.songs().items ?? []
        for item in items {
            // DRM-protected and not-downloaded cloud items cannot be played by our engine; skip them.
            guard item.assetURL != nil, !item.hasProtectedAsset else { continue }
            let pid = item.persistentID
            let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.mediaPersistentID == pid })
            let alreadyImported = (try? context.fetch(descriptor)) ?? []
            if !alreadyImported.isEmpty { continue }
            let track = Track(title: item.title ?? "Unknown Title", source: .mediaLibrary, filePath: "")
            track.mediaPersistentID = pid
            track.artist = item.artist
            track.album = item.albumTitle
            track.albumArtist = item.albumArtist
            track.genre = item.genre
            track.durationSec = item.playbackDuration
            track.format = item.assetURL?.pathExtension.lowercased() ?? "other"
            if let artwork = item.artwork?.image(at: CGSize(width: 300, height: 300)),
               let data = artwork.jpegData(compressionQuality: 0.8) {
                saveArtwork(data, for: track)
            }
            context.insert(track)
        }
        try? context.save()
    }

    // MARK: - Shared upsert

    private func upsert(fileURL: URL, source: TrackSource, storedPath: String,
                        bookmarkID: UUID?, context: ModelContext) async {
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.filePath == storedPath })
        let matches = (try? context.fetch(descriptor)) ?? []
        if let found = matches.first(where: { $0.folderBookmarkID == bookmarkID }) {
            found.isMissing = false
            return
        }
        let meta = await MetadataReader.read(url: fileURL)
        let track = Track(title: meta.title ?? fileURL.deletingPathExtension().lastPathComponent,
                          source: source, filePath: storedPath)
        track.artist = meta.artist
        track.album = meta.album
        track.albumArtist = meta.albumArtist
        track.genre = meta.genre
        track.durationSec = meta.durationSec
        track.format = fileURL.pathExtension.lowercased()
        track.fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        track.folderBookmarkID = bookmarkID
        if let artwork = meta.artwork { saveArtwork(artwork, for: track) }
        context.insert(track)
    }

    private func saveArtwork(_ data: Data, for track: Track) {
        let name = "\(track.id.uuidString).jpg"
        try? data.write(to: LibraryFiles.artworkDirectory.appendingPathComponent(name))
        track.artworkFile = name
    }
}
