# Sonara — versi iOS dari Auralys (rebuild clean-room)

Offline music player untuk iPhone: library lokal (folder pilihan user, file impor,
Music library non-DRM), playback background + lock screen, equalizer 5-band + preset,
bass boost / reverb / virtualizer (pendekatan iOS), playlist unlimited + drag reorder,
smart list (Favorites / Most Played / Recently Added), visualizer, search.

Dokumen perencanaan ada di `replica/` (recon.md, architecture.md, schema.sql,
features.csv, design/, build-log.md).

## Cara jadi file .ipa

Aplikasi iOS **hanya bisa di-compile di macOS dengan Xcode** — tidak ada cara
resmi membuatnya di Linux/Windows. Dua jalur yang sudah disiapkan:

### Jalur A — GitHub Actions (tanpa punya Mac, ±10 menit)
1. Buat repo GitHub baru, upload/push seluruh isi folder ini ke branch `main`.
2. Buka tab **Actions** di repo → workflow **Build IPA** jalan otomatis
   (atau klik *Run workflow*).
3. Setelah hijau, unduh artifact **Sonara-unsigned-ipa** — di dalamnya ada
   `Sonara-unsigned.ipa`.
4. Install ke iPhone: IPA ini *unsigned*, jadi install lewat **AltStore /
   SideStore / Sideloadly** — tool itu menandatanganinya dengan Apple ID kamu
   (gratis, berlaku 7 hari untuk akun free, bisa di-refresh).

### Jalur B — Mac + Xcode (untuk TestFlight / App Store)
1. Buka `Sonara/Sonara.xcodeproj` di Xcode 15+.
2. Signing & Capabilities: pilih Team (akun Apple Developer kamu).
   Bundle ID saat ini `com.xel.sonara` — ganti bila perlu.
3. Product → Archive → Distribute App.

## Catatan jujur soal status kode

Kode ditulis lengkap untuk semua screen di recon (S01–S14), tapi **belum pernah
di-compile** karena lingkungan pembuatannya Linux tanpa Xcode. Sekali build
pertama di Jalur A/B mungkin memunculkan error kompilasi kecil yang perlu
diperbaiki iteratif — workflow Actions akan menunjukkan error-nya baris per baris.
Yang memang disederhanakan (lihat `replica/build-log.md`): visualizer memakai
level meter per potongan buffer (bukan FFT penuh), dan FLAC bergantung pada
dukungan AVFoundation (bila ada file yang gagal, jalur decoder FFmpegKit adalah
langkah berikutnya di architecture.md).

Nama "Sonara" adalah nama kerja — cek merek dagang & domain sebelum rilis publik.
