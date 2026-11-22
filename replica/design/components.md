# Components — Sonara (iOS, SwiftUI)

Tokens: `tokens.json` in this folder; implemented as `Theme.swift` (Color assets + constants). No raw hex in views except via Theme.

MiniPlayerBar
  variants  playing, paused
  states    no track (hidden), track loaded
  tokens    bg surface, height 64, radius lg (floating, 16pt margins)
  a11y      buttons labelled Play/Pause/Next; whole bar is a button to Now Playing
  used on   all tabs (S03–S07, S11–S13)

TrackRow
  variants  with artwork, placeholder artwork (musical note icon, SF Symbols)
  states    default, currently playing (accent equalizer icon), favorite (heart.fill)
  tokens    bg clear/surface, text body, textMuted footnote
  a11y      row is a button; context menu has VoiceOver actions (Play, Add to Playlist, Favorite)
  used on   S04, S07, S12, S13

AlbumCell
  variants  grid (2–3 cols), list
  states    default, missing artwork (gradient placeholder + initials)
  used on   S05

SmartCard
  variants  Favorites, Most Played, Recently Added
  states    empty (count 0), filled
  tokens    bg surfaceRaised, radius lg, icon accent
  used on   S03

PresetChip
  variants  Flat, Classical, Jazz, Rock, Pop, Hip-Hop, Heavy Metal, Custom
  states    selected (accent bg, onAccent text), unselected (surface, text)
  used on   S10

EQBandSlider
  variants  5 bands: 60 / 230 / 910 / 3.6k / 14k Hz
  states    default; any manual change switches preset to Custom
  tokens    range -12…+12 dB
  used on   S10

VisualizerView
  variants  bars (24), driven by audio levels at ~30fps
  states    playing (animating), paused (decays to rest)
  tokens    accent bars on clear bg
  used on   S08

PermissionExplainer (Onboarding)
  variants  three source cards: Folder, Import Files, Music Library
  states    none granted, some granted, scan running, scan done
  used on   S01, S02 (progress shown inline)

EmptyState
  variants  no tracks, no playlists, no search results, folder missing
  states    with primary action (Choose Folder / Import)
  used on   S03–S07, S11
