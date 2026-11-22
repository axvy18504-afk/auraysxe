# Architecture: Auralys versi iOS (rebuild clean-room, nama kerja — rebrand sebelum rilis)

Membaca: `replica/recon.md` (14 screen, 7 flow, 7 entitas) + `replica/features.csv` (must 14, should 7, could 4, skip 3).

Perbedaan mendasar dari template architect bawaan: aplikasi ini **offline, tanpa server, tanpa akun, tanpa pembayaran**. Jadi tidak ada Postgres, auth, API HTTP, webhook, atau email. Semua "backend" adalah penyimpanan lokal di perangkat. Yang di bawah adalah padanan iOS-nya per lapisan.

## Stack

| layer | choice | why |
| --- | --- | --- |
| platform | iOS 17+ (iPhone), Swift 5.9+ | Target tunggal; iOS 17 membuka SwiftData & API modern |
| UI | SwiftUI | Standar iOS saat ini, cocok untuk list/grid player; padanan "mobile: SwiftUI" dari template |
| audio engine | AVFoundation — AVAudioEngine + AVPlayer/AVAudioPlayerNode | Kontrol penuh atas rantai EQ/reverb; AVPlayer polos tidak bisa EQ kustom |
| DSP / EQ | AVAudioUnitEQ (multi-band parametric), AVAudioUnitReverb, low-shelf untuk bass boost, DSP widening custom (mid/side gain) | Bass boost & virtualiser Android tidak ada padanan 1:1 — ini pendekatan terdekat |
| decoder ekstra | FFmpegKit atau VLCKit (SPM/CocoaPods) | Untuk FLAC & format yang tidak didukung AVFoundation secara native |
| metadata | AVAsset + MediaPlayer (MPMediaQuery) | Baca ID3/metadata + artwork; MediaPlayer untuk lagu dari library Musik user (non-DRM saja) |
| database lokal | SwiftData (di atas SQLite) | Pengganti "database" template: satu store lokal, relasi Playlist—Track, migrasi skema bawaan |
| file access | Security-scoped bookmarks (folder picker) + File Sharing / impor ke sandbox + Media Library | Tiga jalur resmi iOS; tidak ada scan storage total seperti Android |
| background audio | AVAudioSession (.playback) + MPRemoteCommandCenter + MPNowPlayingInfoCenter | Playback lanjut saat layar mati, kontrol lock screen & AirPods/Bluetooth |
| visualizer | AVAudioEngine tap (FFT) → Metal atau SwiftUI Canvas | Data frekuensi real-time untuk gelombang/tema |
| distribusi | Xcode → TestFlight → App Store (Apple Developer Program, $99/thn) | Satu-satunya jalur resmi untuk user lain; sideload gratis hanya 7 hari & perangkat sendiri |
| auth / payments / email / hosting | **tidak ada** | Aplikasi tanpa akun & tanpa server — sesuai produk aslinya |

Prinsip template tetap berlaku: satu database (lokal), tanpa microservices, teknologi membosankan yang terdokumentasi.

## Schema

Tables: 5 tabel nyata + 2 view turunan (Album, Folder) + 2 singleton settings. Lihat `replica/schema.sql` untuk DDL SQLite ekuivalen (SwiftData menghasilkan skema yang sama).

Aturan akses: tidak ada multi-user — semua data milik pemilik perangkat. "Access rule"-nya adalah sandbox iOS itu sendiri + security-scoped bookmark untuk folder di luar sandbox.

Keputusan penting:
- `track.source` membedakan asal file: `imported` (salinan di sandbox), `folderBookmark` (referensi folder user), `mediaLibrary` (persistentID MediaPlayer, tanpa path file). Playback & scan memperlakukan ketiganya berbeda.
- Urutan playlist disimpan sebagai `position` integer di `playlist_item` (bukan array di playlist), agar drag-and-drop reorder = update baris.
- `play_count` + `last_played_at` di `track` cukup untuk Most Played; tabel PlayHistory penuh ditunda (could) — Recently Added cukup dari `date_added`.
- Artwork disimpan sebagai file di sandbox (`artwork/<hash>.jpg`), bukan blob di database, agar library FLAC besar tidak menggelembungkan store.
- Constraint keras: `unique(file_path)` untuk file sandbox/bookmark dan `unique(source, media_persistent_id)` untuk Media Library — scan ulang tidak boleh menduplikasi lagu (masalah klasik port semacam ini, diselesaikan di database, bukan UI).

## API

Tidak ada API jaringan. Padanannya: **service layer lokal**, satu baris per flow recon.

| service / method | does | who | input | output | flow |
| --- | --- | --- | --- | --- | --- |
| LibraryService.grantFolder() | Buka document picker, simpan security-scoped bookmark folder | user | folder URL | bookmark record | F01 |
| LibraryService.importFiles(urls) | Salin file dari Files/share sheet ke sandbox Music/ | user | [URL] | [Track] baru | F01 |
| LibraryService.scan() | Enumerasi folder bookmark + sandbox, baca metadata, upsert Track (tanpa duplikat) | sistem/user | — | ringkasan scan (baru/berubah/hilang) | F01 |
| LibraryService.syncMediaLibrary() | Query MPMediaQuery, upsert track non-DRM | user (izin Media Library) | — | [Track] | F01 |
| PlayerEngine.play(queue, startIndex) | Bangun queue, mulai playback lewat AVAudioEngine | user | [trackId], index | state playing | F02, F03, F06 |
| PlayerEngine.togglePlayPause / next / previous / seek(sec) | Kontrol transport | user & remote commands | — | state | F02 |
| PlayerEngine.setRepeat / setShuffle | Mode putar | user | mode | — | F02 |
| AudioGraph.applyEQ(settings) | Terapkan band gains + bass boost + reverb + widening ke rantai audio | user | EQSettings | — | F04 |
| AudioGraph.fftStream | Tap buffer → FFT untuk visualizer | sistem | — | [Float] bins @ ~30fps | F02 |
| PlaylistService.create / rename / delete | Kelola playlist | user | nama | Playlist | F05 |
| PlaylistService.add(trackId) / remove(itemId) / move(from, to) | Kelola isi & urutan playlist | user | id | PlaylistItem terupdate | F05 |
| SmartListService.favorites / mostPlayed(limit) / recentlyAdded(limit) | Query turunan dari Track | sistem | limit | [Track] | F06 |
| SettingsService.saveEQ / saveTheme | Persistensi EQ & tema (bertahan saat update aplikasi) | user | settings | — | F04, F07 |
| MigrationService (SwiftData VersionedSchema) | Migrasi skema antar versi aplikasi | sistem | versi lama | versi baru | F07 |

Webhooks in: tidak ada. Webhooks out: tidak ada.
Jobs (lokal, bukan server): scan incremental saat launch bila folder berubah (bandingkan mtime), pembersihan artwork yatim (cache), perhitungan ulang playCount tidak diperlukan (inkremental saat lagu selesai diputar ≥ 50% atau selesai — putuskan di build, catat di sini: **selesai diputar atau seek melewati 90%**).

## The parts that bite

- **Sandbox & izin (pengganti "time zones" di template — risiko #1 di sini):** folder bookmark bisa dicabut user / folder dipindah → track jadi yatim. Tangani: tandai `missing`, tawarkan relink, jangan hapus playlist item-nya.
- **Media Library ≠ file bebas:** lagu Apple Music ber-DRM dan lagu iCloud yang belum diunduh tidak bisa diputar engine sendiri. Filter sejak sync, beri label di UI, jangan biarkan gagal diam-diam saat play.
- **Format campuran:** AVFoundation kuat di MP3/AAC/M4A/WAV, lemah di FLAC/OGG. Jalur decoder kedua (FFmpeg/VLC) berarti dua jalur playback — samakan antarmukanya di PlayerEngine agar EQ tetap berlaku untuk semua.
- **EQ tidak identik:** preset Android (angka gain per band dari AudioFX) tidak diketahui publik & tidak boleh ditebak sebagai "sama". Buat preset sendiri dengan karakter genre yang setara, beri nama genre yang sama (nama genre bukan milik siapa pun).
- **Background & interupsi:** panggilan masuk, Siri, rute Bluetooth berubah → AVAudioSession interruption/route-change notification wajib ditangani, posisi putar dipersistensikan berkala agar bisa resume setelah aplikasi dibunuh sistem.
- **Library besar:** 10.000+ file FLAC — scan harus incremental & di background actor, artwork di-resize (300×300) & di-cache di disk, list memakai lazy loading.
- **Idempotensi scan:** scan yang terputus di tengah tidak boleh menghasilkan duplikat atau menghapus track yang sebenarnya masih ada — upsert dulu, sweep "missing" hanya setelah scan tuntas penuh.
- **Migrasi data (F07):** playlist/favorites/settings adalah satu-satunya "harta" user — setiap rilis yang mengubah skema wajib VersionedSchema + tes migrasi dari versi sebelumnya.
- **App Review:** aplikasi pemutar file lokal aman secara kebijakan, tapi hindari kata/klaim yang menyiratkan katalog streaming atau afiliasi dengan Auralys; rebrand penuh sebelum submit (replica-brand + sweep).

## Build order

1. **Vertical slice (F01 + F02, ±1 minggu):** S01 (folder picker + impor) → S02 scan 1 folder → S04 Songs → S08 Now Playing polos (play/pause/seek/next/prev) + background playback & lock screen. Membuktikan tiga risiko terbesar sekaligus: akses file, engine, background.
2. **Must-haves:** S05 Albums, S06 Folders, S07 Search, S10 Equalizer + preset, S11–S12 Playlists (buat/long-press tambah/drag reorder), S13 Smart lists (ketiganya), decoder FLAC.
3. **Should-haves:** bass boost (low-shelf), reverb, virtualiser (mid/side), visualizer FFT di S08, S09 Queue, scan ulang manual + incremental.
4. **Could-haves:** tema 3D tambahan, CarPlay, sleep timer, crossfade/gapless.
5. **Fixes from replica-entrepreneur:** jalankan setelah ada versi yang bisa dipakai — membaca keluhan user Android soal Auralys (mis. dari review publik) untuk membedakan versi iOS ini.

Ringkasan: stack SwiftUI + AVAudioEngine + SwiftData, 100% lokal. Tabel: 5 (+2 view, 2 singleton). Route/service: 14 method lokal, 0 endpoint jaringan. Tiga risiko terbesar: (1) akses file sandbox vs ekspektasi scan-total Android, (2) kesetaraan EQ/bass/virtualiser, (3) lagu Media Library ber-DRM/iCloud yang tidak bisa diputar.
Next step: `/replica-design` — design system & token versi iOS (dengan identitas visual baru, bukan milik Auralys).
