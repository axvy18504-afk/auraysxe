# Build log — Sonara (iOS rebuild of Auralys)

Date: 2026-11-22. Build environment note: code authored on Linux (no Xcode), so
nothing here has been compiled yet — first compile happens via the GitHub
Actions workflow (macos-14) or Xcode on a Mac. Statuses below mean
"implemented in source", not "verified running".

| ID | screen | status | notes |
| --- | --- | --- | --- |
| S01 | Onboarding / sources | done (source) | Folder picker + file import + Music Library as three source cards (SourcesView) |
| S02 | Scan progress | done (source) | Progress + message inline in SourcesView and Settings; incremental upsert, anti-duplicate constraint |
| S03 | Home | done (source) | Smart cards + Recently Added / Most Played previews, mini player overlay |
| S04 | Songs | done (source) | TrackList with context menu (favorite, add to playlist) |
| S05 | Albums | done (source) | Grouped from track metadata |
| S06 | Folders | done (source) | Per bookmarked folder + Imported + Music Library sections |
| S07 | Search | done (source) | Title/artist/album, empty states |
| S08 | Now Playing | done (source) | Seek (segment scheduling), shuffle/repeat, favorite, visualizer (level-meter bars, not full FFT — partial) |
| S09 | Queue | done (source) | Tap to jump, swipe to remove non-current |
| S10 | Equalizer | done (source) | 5-band AVAudioUnitEQ, 7 own presets + Custom, bass boost (low-band gain), reverb, virtualizer (presence/reverb blend) — approximations, documented |
| S11 | Playlists | done (source) | Create via alert, counts |
| S12 | Playlist detail | done (source) | Drag reorder (EditButton + onMove), swipe delete, rename, delete playlist |
| S13 | Smart lists | done (source) | Favorites / Most Played (play counted after 10 s) / Recently Added |
| S14 | Settings | done (source) | Library counts, rescan, sources sheet, EQ link, about |

Harder than expected / known risks for first compile:
- SwiftData predicates on optional/UInt64 fields (mediaPersistentID) may need
  adjusting if the compiler rejects them.
- AVAudioPlayerNode segment completion also fires on stop/seek; guarded by an
  end-of-file check in PlayerEngine.trackFinished().
- FLAC relies on AVFoundation support; FFmpegKit decoder is the documented
  fallback (architecture.md) and is NOT integrated yet — partial.
- App icon is a placeholder asset catalog (no images yet).
