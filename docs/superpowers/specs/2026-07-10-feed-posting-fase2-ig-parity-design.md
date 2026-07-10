# Feed Posting Fase 2 — Redesign Menyamai IG (Design Spec)

**Tanggal:** 2026-07-10
**Status:** Disetujui user (mockup v2 + upgrade poin 1–10)
**Prasyarat:** Fase 1 reliability MERGED (PR #72) — `VideoCompressGate` wajib jadi satu-satunya pintu kompresi, TUS auto-retry aktif.
**Referensi:** mockup v2 (5 layar, sesi 2026-07-10), screenshot IG di `C:\Users\USER\Desktop\IG\`, riset chrome feed (`_FeedPostView` di `feed_screen.dart`).

## Tujuan

Flow posting (foto, carousel foto, video) menyamai Instagram dari awal pilih media sampai dipost — rapi dan premium — dengan batas kemampuan yang jujur: **tanpa musik/voiceover, tanpa teks/stiker di atas video, carousel = foto saja**.

Bug yang dituntaskan fase ini: **#3 suara tidak keluar di pratinjau** dan **#4 pratinjau tidak sesuai kondisi feed** (rail mockup palsu angka "0").

## Alur target

```
Post Baru (galeri campur foto+video, satu layar)
 ├─ pilih VIDEO ──────────────→ Edit Video (fullscreen) ─→ Bagikan ─→ Pratinjau / Ubah Sampul
 └─ pilih FOTO (multi ≤8 = carousel) ─────────────────────→ Bagikan ─→ Pratinjau
```

Video single; carousel foto-saja maksimal 8 (kemampuan existing). Jalur foto melewati Edit Video.

## Struktur eksekusi: 3 sub-fase, plan terpisah per sub-fase

Urutan wajib: **2A (fondasi) → 2B (layar) → 2C (produk)**. 2B bergantung pada widget bersama & pipeline 2A; 2C menempel di layar hasil 2B.

---

## Sub-fase 2A — Fondasi teknik

### 2A-1. Widget chrome feed bersama (anti-drift)
Ekstrak chrome video/foto post dari `feed_screen.dart` (`_FeedPostView` dkk.) menjadi widget reusable di `lib/features/feed/widgets/` — minimal: rail aksi kanan (like/comment/share/cart/more, ikon 30 stroke 1.7, angka 12 w600, item spacing 18, rail `right:4`), overlay kreator (avatar 34 border putih 1.4, username 13.5 w600, chip Ikuti radius 9 padding h11 v5), caption expandable (13.2 w600, 2 baris), kartu produk anchor (blur, bg black .52, border white .16, radius 14, tombol keranjang oranye `#FF7A00` 34×34), scrim bawah 330px (transparent→black .76), scrubber (2px, thumb 12 saat drag).
- Feed asli **dan** layar Pratinjau memakai widget yang sama; Pratinjau mengoper data pura-pura (angka contoh, non-interaktif) lewat parameter, bukan menyalin layout.
- Perilaku feed publik TIDAK berubah — refactor murni, diverifikasi golden/widget test + visual.

### 2A-2. "Next" instan — trim+kompres pindah ke background (Approach B)
- Layar Edit Video tidak lagi mengkompres saat Next. `FeedCreatePostDraft` menambah field `trimStart`/`trimDuration` (rentang pilihan user); Next hanya menyimpan rentang → langsung ke Bagikan.
- `FeedUploadStore._runVideoUpload` mengkompres SEKALI via `videoCompressGate.compress(..., startTime: trimStart, duration: trimDuration)` saat upload dimulai. `trimmedVideoPath` tetap dipakai bila hasil re-edit lama ada (kompatibel mundur).
- Error kompresi muncul di relay card (tombol Coba Lagi existing). `_ProcessingPanel` + PopScope menunggu-kompres di layar trim DIHAPUS (tidak ada lagi proses yang ditunggu di layar).

### 2A-3. Pre-flight check media
Sebelum masuk pipeline (saat pilih di galeri): validasi durasi ≥1s & ≤batas (video >60s → wajib trim, sudah ada), ukuran ≤200MB, dan **coba init `VideoPlayerController` sekali** — gagal init = format tidak didukung (HDR/codec aneh) → pesan spesifik "Format video ini belum didukung. Coba video lain atau rekam ulang." SEBELUM user menulis caption, bukan gagal misterius di tengah upload.

### 2A-4. Telemetri funnel posting
Pakai infra existing `AppAnalytics.logEvent` (Firebase, `lib/services/app_analytics.dart`). Event (fire-and-forget, gagal diam):
`feed_post_pick_opened`, `feed_post_media_selected` (param `type`: video/photo/carousel, `count`), `feed_post_edit_opened`, `feed_post_share_opened`, `feed_post_preview_opened`, `feed_post_submitted`, `feed_post_upload_success`, `feed_post_upload_failed` (param `step`, `reason`). Tujuan: drop-off & failure-rate kelihatan tanpa menunggu keluhan.

---

## Sub-fase 2B — Lima layar (visual sesuai mockup v2)

Token dipakai lintas layar (dari kode nyata): biru aksi `#1E5BFF`; dark editor bg `#05070D`, card `#11141B`, border `#252A35`, muted `#AEB7C7`; light ink `#101828`, muted `#667085`, border `#E0E7F0`, soft `#F5F8FF`, hint `#98A2B3`; font PlusJakartaSans; tombol bulat header 36–44; radius tombol 14–18, kartu 16–20, media 18–26; pill frosted `rgba(255,255,255,0.06-0.08)` + border `rgba(255,255,255,0.14)`.

### 2B-1. "Post Baru" — galeri campur (extend `FeedMediaPickerScreen`)
Picker in-app existing (`feed_media_picker_screen.dart`, `photo_manager`, sudah `RequestType.common`) diperluas:
- Grid 4 kolom campur foto+video; tile video berlencana durasi (pill kecil kanan-bawah + ikon play); tile kamera pertama.
- Preview besar di atas grid (media tersorot), counter "Foto X dari Y" saat multi.
- "Pilih banyak": multi-select foto dengan badge nomor biru (urutan = urutan slide); pilih video menonaktifkan multi (video single). Maks 8 foto.
- Header: X kiri, judul "Post Baru", tombol lanjut bulat biru kanan (chevron). Lanjut: video → Edit Video; foto → Bagikan.
- Layar `FeedVideoStartScreen` (2 tombol + OS picker) PENSIUN dari flow post (entry post memakai picker ini).

### 2B-2. "Edit Video" — satu editor fullscreen (jalur video saja)
Gabungkan `FeedVideoPreviewScreen` + `FeedVideoTrimScreen` jadi SATU layar:
- Video hampir edge-to-edge; kontrol mengambang frosted: back bulat kiri-atas, Next bulat biru kanan-atas; timecode `m:ss / m:ss` + pill "Suara" overlay bawah video; tap video = play/pause.
- **Suara aktif** (volume ikut `feedMuted`, lihat 2C-6).
- Timeline filmstrip (frame thumbnails existing) + 2 handle putih + dim di luar seleksi; baris "0:44 dipilih · Maksimal 60 detik"; marker 0:00/total.
- Toolbar bawah 2 pill frosted: **Potong** (fokus timeline) & **Sampul** (buka Ubah Sampul) — JUJUR tanpa Audio/Text/Voice/Captions.
- Next instan (2A-2). Video ≤60s default seleksi penuh — tetap lewat layar ini (bisa langsung Next).

### 2B-3. "Bagikan" — lembar detail (perombakan `FeedNewPostScreen`)
- Thumbnail media kecil di tengah: varian video = pill "Pratinjau" (kiri-atas) + "Ubah sampul" (bawah); varian carousel = counter `1/3` + titik indikator + pill "Pratinjau" (sampul carousel = foto pertama, tanpa Ubah sampul).
- Caption trigger existing (modal) dipertahankan; divider hairline.
- "Tag Produk Pernah Dibeli" dipertahankan (pengganti "Tag people" IG — nilai khas Natalo).
- Bottom bar: **Simpan Draft** (soft `#F5F8FF`, teks biru) + **Bagikan** (biru) berdampingan, tinggi 50–56, radius 16–18. Sheet keluar (`_LeaveDraftSheet`) tetap ada untuk back-with-progress.

### 2B-4. "Pratinjau" — chrome feed ASLI + suara ★
Rombak `FeedPostPreviewScreen`:
- Render memakai **widget bersama 2A-1** — rail, kartu produk (dari produk yang ditag), identitas kreator (profil user), caption, scrim, scrubber tampil PERSIS feed. Non-interaktif (IgnorePointer di rail) dengan angka contoh; keranjang badge tampil bila ada produk tertag.
- **Suara AKTIF**: hapus `setVolume(0)`; volume ikut `feedMuted` + pill toggle "Suara" kanan-atas (2C-6).
- Header overlay: back bulat, judul "Pratinjau", pill Suara. Bottom bar hitam: Simpan Draft + Bagikan berdampingan.
- Carousel foto: PageView + counter + titik, tanpa scrubber. Ini penutup bug #3 & #4.

### 2B-5. "Ubah Sampul" — scrubber frame bebas
Ganti `_CoverPickerSheet` (3 preset) dengan layar penuh light:
- Header: X, judul "Ubah Sampul", ✓ bulat biru.
- Preview sampul besar (frame terpilih, timecode badge) + filmstrip frame dengan **kotak seleksi biru digeser bebas** (frame luar seleksi diredupkan putih .55). Frame extraction reuse pola `_extractFrameThumbnails`.
- Tombol "Ambil dari galeri" (sampul dari gambar galeri, `image_picker` existing).

---

## Sub-fase 2C — Upgrade produk

### 2C-1. Draft sungguhan
- Ganti slot tunggal `natalo-feed-upload-pending` → daftar draft JSON di SharedPreferences (`natalo-feed-drafts`, berisi type/caption/productIds/media paths/thumbnail/trimStart/trimDuration/savedAt) + **migrasi otomatis** key lama.
- Saat load: validasi `File.exists` tiap media — file hilang → draft ditandai rusak & bisa dihapus, tidak jadi zombie.
- UI: bagian "Draft" ber-thumbnail di layar Postingan Saya (`member_posts_screen.dart`); tap → buka Bagikan dengan isi ter-restore (caption, produk, trim, sampul).

### 2C-2. Lanjutkan upload setelah app ditutup
- `FeedUploadStore` menyimpan metadata task aktif (draft + status) ke prefs saat mulai; hapus saat sukses/dibatalkan.
- Cold start: bila ada task 'uploading' tertinggal + file masih ada → banner/relay "Lanjutkan upload?" → mulai ulang pipeline; TUS fingerprint store existing melanjutkan dari byte terakhir; bila signature Bunny kadaluarsa → re-provision otomatis.

### 2C-3. Carousel: urutkan & hapus
Di layar Bagikan varian carousel: rail thumbnail slide (drag untuk urut ulang — `ReorderableListView` horizontal; tombol × per slide untuk hapus; minimal 1 tersisa). Counter/titik preview mengikuti.

### 2C-4. Autocomplete @mention di caption
Di editor caption (`feed_caption_edit_screen.dart`): ketik `@` → panel saran user (reuse endpoint pencarian user dari `feed_user_search_screen.dart`), tap → sisip `@username`. Feed sudah merender mention biru + tap ke profil — ini menutup lingkarannya.

### 2C-5. Micro-interactions
- Hero transition tile galeri → preview besar; transisi antar layar halus (fade-through); badge nomor carousel scale-in; `AppHaptics.selection` saat pilih media / geser handle mencapai batas; tombol Bagikan pressed-scale. Durasi 150–350ms, tanpa jank (profile mode check).

### 2C-6. Suara sinkron `feedMuted`
Semua controller di flow (Edit Video, preview media di layar Bagikan, Pratinjau) set `volume = appSettingsStore.feedMuted ? 0 : 1`; pill "Suara" men-toggle `appSettingsStore.setFeedMuted` (persist, sinkron dengan feed publik). Default global existing = muted; sekali user menyalakan di feed/pratinjau, seluruh app konsisten.

---

## Non-goals (fase ini)
- Musik / audio picker / voiceover / waveform.
- Teks, stiker, caption-on-video (burn-in) — kandidat Fase 3.
- Campur video+foto dalam satu carousel; multi-video.
- Filter/efek visual; crop rasio foto lanjutan; tag lokasi/orang ala IG.
- Perubahan perilaku feed publik (2A-1 refactor murni).

## Testing
- `flutter analyze` bersih + seluruh widget test hijau per sub-fase.
- 2A-1: widget test chrome bersama (feed & pratinjau memakai widget sama); golden bila stabil.
- 2A-2: unit test store (kompres dipanggil dengan trimStart/trimDuration; draft tanpa trim tetap jalan).
- 2C-1: unit test migrasi draft + validasi file hilang.
- Device-verify per sub-fase (plugin native): galeri campur di HP, suara nyala di edit/pratinjau, drag handle & scrubber sampul mulus, reorder carousel, resume upload setelah force-close.

## Catatan implementasi
- Semua kompresi TETAP lewat `VideoCompressGate` (aturan Fase 1 — jangan panggil plugin langsung).
- File besar yang dirombak berat (`feed_video_upload_flow.dart` 2700+ baris) dipecah per layar ke file terpisah di `lib/screens/feed_post/` saat 2B — satu layar satu file.
- Copy Indonesia konsisten dengan app ("Pratinjau", "Ubah Sampul", "Simpan Draft", "Bagikan").
