import Foundation
import SwiftData

enum TrackSource: String, Codable {
    case imported
    case folderBookmark
    case mediaLibrary
}

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var durationSec: Double
    var format: String
    var fileSize: Int64
    var dateAdded: Date
    var playCount: Int
    var lastPlayedAt: Date?
    var isFavorite: Bool
    var isMissing: Bool
    var sourceRaw: String
    /// imported: file name inside Documents/Music. folderBookmark: path relative to the bookmarked folder. mediaLibrary: unused.
    var filePath: String
    var folderBookmarkID: UUID?
    var mediaPersistentID: UInt64?
    var artworkFile: String?

    init(id: UUID = UUID(), title: String, source: TrackSource, filePath: String) {
        self.id = id
        self.title = title
        self.durationSec = 0
        self.format = "other"
        self.fileSize = 0
        self.dateAdded = Date()
        self.playCount = 0
        self.isFavorite = false
        self.isMissing = false
        self.sourceRaw = source.rawValue
        self.filePath = filePath
    }

    var source: TrackSource { TrackSource(rawValue: sourceRaw) ?? .imported }
    var artistDisplay: String { artist ?? "Unknown Artist" }
    var albumDisplay: String { album ?? "Unknown Album" }
}

@Model
final class FolderBookmark {
    @Attribute(.unique) var id: UUID
    var bookmarkData: Data
    var displayName: String
    var lastScannedAt: Date?

    init(id: UUID = UUID(), bookmarkData: Data, displayName: String) {
        self.id = id
        self.bookmarkData = bookmarkData
        self.displayName = displayName
    }
}

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \PlaylistItem.playlist)
    var items: [PlaylistItem]

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = []
    }

    var sortedItems: [PlaylistItem] { items.sorted { $0.position < $1.position } }
}

@Model
final class PlaylistItem {
    @Attribute(.unique) var id: UUID
    var position: Int
    var addedAt: Date
    var playlist: Playlist?
    var track: Track?

    init(id: UUID = UUID(), position: Int, track: Track?) {
        self.id = id
        self.position = position
        self.addedAt = Date()
        self.track = track
    }
}
