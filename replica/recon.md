# Recon map: Auralys (Android) → port iOS

Scope: Seluruh fitur inti Auralys Music App v4.1.0 (offline music player) — library lokal, playback, equalizer/sound tools, playlist, smart list, visualizer. Bukan streaming, bukan katalog.
For: xel — versi iOS milik sendiri (clean-room rebuild; nama/logo/teks asli tidak dipakai, rebrand sebelum rilis)
Date: 2026-11-22
Original: Android, package com.auralyst.app, v4.1.0, 34,35 MB, gratis, tanpa akun

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | marketing site / homepage | https://auralys.net/ | Pitch, daftar fitur lengkap, format, EQ, playlist, troubleshooting, FAQ |
| 2 | download page | https://auralys.net/download/ | Detail APK (versi, package, ukuran), langkah install, izin storage, FAQ download |
| 3 | about page | https://auralys.net/about/ | Posisi produk: player untuk library milik sendiri (rips, downloads, studio exports) |
| 4 | guides (dari halaman download) | https://auralys.net/download/ | "How to Install on Android", "Equalizer: Presets, Bass Boost and Honest Tuning", "Offline Playback", "Playlists in Auralys" |
| 5 | blog: Auralys on PC | https://auralys.net/blog/auralys-for-pc-guide/ | Kebiasaan library: satu master folder di PC, mirror ke HP; Recently Added untuk verifikasi |

Catatan metode: hanya sumber publik. Tidak ada decompile APK, tidak ada login, tidak ada screenshot aplikasi asli yang disimpan (situs hanya mendeskripsikan layar secara tekstual: home dengan smart cards, Liked Songs, playlist shelf, now playing bar).

## Core loop

User membuka aplikasi → aplikasi memindai file musik lokal di perangkat → user menekan play pada lagu/album/folder → lagu diputar offline dengan tuning EQ pilihannya. (Happy path: 2–3 tap dari library ke playback.)

## Screens

| ID | screen | route / how to reach | purpose | key components | states seen |
| --- | --- | --- | --- | --- | --- |
| S01 | Onboarding / permission | Launch pertama | Minta izin akses storage agar scan bisa jalan | Penjelasan izin, tombol grant | Belum diizinkan, diizinkan, ditolak (library kosong) |
| S02 | Library scan (progress) | Setelah izin diberikan | Memindai file & membangun library | Progress, hitungan lagu ditemukan | Scanning, selesai, gagal/parsial |
| S03 | Home | Tab utama | Pintu masuk: smart cards (Favorites, Most Played, Recently Added), playlist shelf | Smart cards, playlist shelf, now playing bar (mini player) | Kosong (belum ada lagu), terisi |
| S04 | Songs list | Home / tab library | Daftar semua lagu, bisa dicari | Search bar, baris lagu (judul, artis, artwork), sort | Kosong, hasil search kosong, terisi |
| S05 | Albums list + album detail | Tab library | Browse per album | Grid/list album, artwork, daftar track album | Kosong, terisi |
| S06 | Folders list | Tab library | Browse per struktur folder file | Daftar folder, breadcrumb | Kosong, terisi |
| S07 | Search results | Search bar S04 | Cari di seluruh file lokal | Search field, hasil campuran lagu/album | Ketik kosong, ada hasil, tanpa hasil |
| S08 | Now Playing | Tap lagu / mini player | Playback penuh + visualizer | Artwork, seek bar, prev/play/next, shuffle, repeat, tombol EQ, visualizer/tema 3D, like (favorite) | Playing, paused, lagu tak bisa diputar (error file) |
| S09 | Queue / Up Next | Dari Now Playing | Antrian putar saat ini | Daftar antrian, reorder | — (diinferensikan dari pola player; confidence medium) |
| S10 | Equalizer | Dari Now Playing / settings | Tuning suara | Sliders multi-band, preset (Classical, Jazz, Rock, Pop, Hip-Hop, Heavy Metal), bass boost, reverb, virtualiser | Preset aktif, custom, flat/reset |
| S11 | Playlists list | Home / tab playlist | Semua playlist user + smart lists | Playlist shelf/list, tombol buat baru | Kosong, terisi |
| S12 | Playlist detail | Tap playlist | Isi playlist, urutan manual | Daftar lagu drag-and-drop reorder, tambah/hapus lagu, long-press untuk buat playlist dari lagu | Kosong, terisi |
| S13 | Smart list detail (Favorites / Most Played / Recently Added) | Smart card di Home | Daftar otomatis yang memelihara dirinya sendiri | Daftar lagu terurut otomatis (play count / tanggal ditambahkan / liked) | Kosong, terisi |
| S14 | Settings | Menu aplikasi | Preferensi player & tema | Pilihan tema 3D/visualizer, opsi scan ulang, output | — (keberadaan tema disebut; rincian settings confidence medium) |

## Flows

```
F01 First run & scan library
    S01 -> S02 -> S03
    happy path clicks: 2 (grant, lalu otomatis scan)
    edge: izin ditolak -> library kosong + penjelasan; file korup terlewati; scan diulang manual

F02 Play a song
    S03/S04/S05/S06 -> S08
    happy path clicks: 2
    edge: file rusak/tidak didukung -> pesan error, skip ke lagu berikut

F03 Search & play
    S04 -> S07 -> S08
    happy path clicks: 3
    edge: tanpa hasil

F04 Tune the sound
    S08 -> S10 (pilih preset atau geser slider, bass boost/reverb/virtualiser) -> S08
    happy path clicks: 2
    edge: output Bluetooth punya processing sendiri -> saran mulai dari flat (dari troubleshooting situs)

F05 Build a playlist
    S04 (long press lagu) -> S11 buat baru -> S12 tambah lagu lain, drag-and-drop reorder
    happy path clicks: 4+
    edge: playlist kosong; hapus lagu dari playlist (file asli tidak ikut terhapus)

F06 Listen via smart list
    S03 smart card -> S13 -> S08
    happy path clicks: 2
    edge: smart list kosong di awal pemakaian (belum ada play history)

F07 Update app without losing data (Android) -> di iOS menjadi: update via App Store
    Playlist, favorites, settings harus bertahan melewati update
    edge: migrasi skema data antar versi
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Mini player / now playing bar | — | playing, paused | S03–S07, S11–S13 |
| Track row | dengan artwork, tanpa artwork | default, playing (highlight), liked | S04, S07, S12, S13 |
| Album cell | grid, list | default | S05 |
| Smart card | Favorites, Most Played, Recently Added | kosong, terisi | S03 |
| Playlist shelf / row | — | kosong, terisi | S03, S11 |
| Search bar | — | kosong, mengetik, hasil kosong | S04, S07 |
| EQ slider band | per frekuensi | default, diubah | S10 |
| Preset chip | Classical, Jazz, Rock, Pop, Hip-Hop, Heavy Metal, Flat/Custom | aktif, tidak aktif | S10 |
| Visualizer canvas | tema 3D / gelombang cahaya | playing (bergerak), paused (diam) | S08 |
| Permission explainer | — | — | S01 |
| Progress indicator (scan) | — | scanning, selesai | S02 |
| Toast / error banner | file error, izin ditolak | — | S02, S08 |

## Inferred data model

```
Track       id, filePath, title, artist, album, albumArtist?, genre?, durationSec,
            format (mp3|wav|flac|aac|m4a|other), fileSize, dateAdded, artworkData?,
            playCount, lastPlayedAt, isFavorite
            evidence: S04–S07, format list di homepage & download page
            confidence: high

Album       id (= kombinasi album + albumArtist), title, artist, artworkData?, year?
            evidence: S05
            confidence: high (entitas turunan dari metadata Track)

Folder      path, name, trackCount
            evidence: S06
            confidence: high (turunan dari filePath Track)

Playlist    id, name, createdAt, updatedAt
            evidence: S11, S12, contoh nama di situs (Winter Vibe, Piano Collection, Daily Mix, Sleep)
            confidence: high

PlaylistItem playlistId, trackId, position
            evidence: S12 drag-and-drop reorder
            confidence: high

EQSettings  presetName, bandGains[ ], bassBoost (0–100), reverb (0–100), virtualizer (0–100),
            isCustom
            evidence: S10, daftar preset di homepage
            confidence: high

PlayHistory trackId, playedAt, completedRatio?
            evidence: S13 Most Played & Recently Added butuh pencatatan putar
            confidence: medium (bisa juga cukup playCount + lastPlayedAt di Track)

AppSettings visualizerTheme, rescanOnLaunch?, lastScanAt
            evidence: tema 3D/visualizer di homepage, F07 data bertahan saat update
            confidence: medium
```

Relationships: Playlist 1—n PlaylistItem n—1 Track; Album & Folder adalah view turunan dari Track (bukan tabel sumber kebenaran); PlayHistory n—1 Track; EQSettings & AppSettings singleton (1 baris).

## Feature matrix

See `features.csv`. Must: 14, should: 7, could: 4, skip: 3.

## Out of scope (cannot or should not be cloned)

- Nama, logo (ikon terracotta sunset), teks/copy dan artwork promosi Auralys — milik mereka; versi iOS wajib rebrand (skill replica-brand).
- Katalog/streaming — Auralys sendiri tidak punya; ia hanya memutar file milik user.
- APK Android itu sendiri — tidak bisa dijalankan/di-sign ulang untuk iOS; ini rebuild clean-room.
- Scan seluruh storage ala Android — secara teknis tidak diizinkan iOS (sandbox); diganti folder picker + impor + Media Library (lihat architecture.md).

## Size

Screens 14, flows 7, entities 7 (3 turunan/singleton). Hard parts: (1) akses file di sandbox iOS, (2) EQ/bass-boost/virtualiser yang tidak 1:1 dengan API Android, (3) playback background + lock screen yang benar, (4) decoding FLAC/format campuran. Tidak ada server, akun, pembayaran, sinkronisasi, atau realtime.
Size: **M** — vertical slice ±1 minggu, versi lengkap setara fitur ±3–5 minggu kerja solo.
