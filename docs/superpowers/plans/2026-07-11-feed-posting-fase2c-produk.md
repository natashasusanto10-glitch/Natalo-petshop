# Feed Posting Fase 2C — Upgrade Produk + Utang 2A/2B (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Melengkapi flow posting hasil 2B dengan kemampuan produk (draft sungguhan + restore video, resume upload setelah app ditutup, urutkan/hapus slide carousel, micro-interactions, sinkronisasi mute) DAN melunasi utang perilaku/kosmetik 2A-2B yang ditemukan gap-scan (cancel-mid-compress salah status, klip 60.x lolos trim, pesan format-tak-didukung hilang, preview sampul low-res, glow ke-clip, ±1.558 baris dead code tambahan).

**Architecture:** Draft pindah dari slot tunggal `natalo-feed-upload-pending` ke daftar JSON `natalo-feed-drafts` (repository kecil + migrasi otomatis) dengan UI daftar ber-thumbnail di Postingan Saya. Resume upload = persist metadata task + hasil provision di `FeedUploadStore`, rehydrate saat cold start via post-frame check, `FeedUploadBar` mendapat state "Lanjutkan upload?". Reorder carousel = `photoFiles` jadi state mutable lokal di layar Bagikan. Micro-interactions = util `fadeThroughRoute` diekstrak dari pola caption editor.

**Tech Stack:** Flutter/Dart; `shared_preferences`, `tus_client_dart` (TusFileStore existing), `videoCompressGate` (WAJIB untuk kompresi). Package: `natalo_petshop_flutter`.

**Spec:** `docs/superpowers/specs/2026-07-10-feed-posting-fase2-ig-parity-design.md` bagian 2C. Task 1–2 = utang di luar spec (temuan review 2A/2B), sisanya = 2C-1..2C-6.

## Global Constraints

- Standar visual "semirip IG, lebih premium" tetap berlaku (frosted pill, tombol bulat 36–44, transisi 150–350ms, haptics, tanpa look default-Flutter). Biru aksi `#1E5BFF`.
- Kompresi HANYA via `videoCompressGate`; analytics via `AppAnalytics.logEvent` fire-and-forget `unawaited`.
- Perilaku FEED PUBLIK tidak berubah (feed_screen hardcode volume kontekstual JANGAN disentuh — lihat Task 6 keputusan).
- Kerja dari `flutter_app/`; tiap task diakhiri `flutter analyze` (lolos bila satu-satunya isu = lint pre-existing `lib/config/launch_popup_campaigns.dart:10`) + `flutter test` penuh hijau + commit dari worktree root (branch `claude/feed-posting-fase2`).
- Widget test: JANGAN `pumpAndSettle` di layar dengan image/shimmer — bounded pump-loop + `SharedPreferences.setMockInitialValues({})`.
- Fakta kode terverifikasi 2026-07-11 (Grep ulang sebelum edit — baris bisa bergeser):
  - Draft save: `feed_new_post_screen.dart:387-411` `_saveDraftAndExit` — key `natalo-feed-upload-pending`, format `'local|post-new|${json}|${ts}'`, payload {type, caption, productIds, media, thumbnailPath, trimStartMs, userPickedCover, savedAt}. Loader: `member_posts_screen.dart` `_loadLocalDrafts` :163-178 (umur <24 jam), `_DraftReminderBanner` (chip biru `#F2F7FF`/`#D9E9FF` radius 18, auto-hide 7 dtk + on-scroll), `_tryRestoreComposerDraft` :247-307 — **video di-skip hardcoded** (:270 `if (type != 'image' ...) return false`), foto restore via `FeedNewPostScreen(prefilledCaption:, prefilledProductIds:)`, draft dihapus hanya saat publish sukses.
  - Resume: `feed_upload_store.dart` TIDAK persist apa pun (grep SharedPreferences = 0). `bunny_upload_service.dart`: TUS `TusFileStore` di `<docs>/feed_uploads/`, fingerprint = path file (resume valid selama path sama); `provisionUpload` TIDAK idempotent (tiap panggil = Bunny guid baru + row FeedPost baru); `authExpire` window **1 jam** (server `lib/feed/bunny.ts:440-467`); TIDAK ada endpoint cleanup orphan yang bisa dipanggil client.
  - Cold-start pattern contoh: `LaunchPromoGate` (`lib/widgets/launch_promo_gate.dart` :69-72 postFrameCallback + `_ran` guard + `_ensureAuthReady` + settle delay + seam injectable). `feedUploadStore` = singleton lazy, tidak diinisialisasi siapa pun. `FeedUploadBar` dirender HANYA di `home_screen.dart:674`.
  - Carousel: `NewPostMediaDraft.photoFiles` immutable; referensi yang harus pindah ke state mutable: `_NewPostThumbnail(draft:...)` render PageView :567-667, counter+dots, `_upload()` :361, `_hasProgress` :108-113, `_saveDraftAndExit` :396-398. `_photoIndex`/`_photoPageController` sudah ada. File foto SUDAH pre-cropped final dari picker.
  - **@mention SUDAH TERPASANG LENGKAP** (dibangun paralel di luar fase ini): `lib/widgets/mention_picker.dart` (MentionUser, MentionPickerController — deteksi `@` anti-email, debounce 200ms → `/api/users/search?q=&limit=8`, insertMention; `MentionSuggestionsPanel`) sudah di-wire di `feed_caption_edit_screen.dart:42-64,181-191`. Render feed via `utils/mention_text.dart`. 2C-4 = TEST REGRESI saja, bukan bangun.
  - Transisi: `showCaptionEditModal` (`feed_caption_edit_screen.dart:271-293`) = PageRouteBuilder fade 180/140ms inline, BELUM jadi util reusable; semua push flow lain = MaterialPageRoute default. `app_motion.dart` cuma entry-animation item, bukan route.
  - Mute audit: SUDAH ikut feedMuted → editor `feed_video_edit_screen.dart:113`, pratinjau `feed_post_preview_screen.dart:94-96`, feed `feed_screen.dart:2027,2247`. Hardcode DISENGAJA (jangan sentuh): picker preview `feed_media_picker_screen.dart:513` (muted by design ala IG), feed_screen `:476,:505` (preload) & `:3802,:3814` (kontekstual). PERLU AUDIT: `member_post_detail_screen.dart` `_muted` lokal `:1891,:1944,:2083(setVolume(1) hardcode),:2117` — cek init dari feedMuted + write-back.
  - Utang perilaku (lokasi presisi): (a) **cancel-mid-compress** `feed_upload_store.dart:376-391` — `gate.cancel` bikin compress throw → `if (range.startTimeSec != null) rethrow;` (:385) menang atas `_checkCancel()` (:394) → status `failed` bukan `cancelled`; fix: `if (range.startTimeSec != null && !_cancelRequested) rethrow;`. (b) **60.x detik** `feed_video_edit_screen.dart:70` (`_duration.inSeconds > 60` — 60.7s lolos) & `:300-301` (`isFullRange` pakai inSeconds) → bandingkan `inMilliseconds`. (c) **format-tak-didukung**: `feed_media_picker_screen.dart` `_ensureVideoController:498-524` catch silent → tambah state `_previewVideoError` + pesan; `_selectVideo:676-717` catch generik. (d) **cover preview low-res**: `feed_cover_picker_screen.dart:89-98` — satu `_extract` (maxWidth 120 q50) dipakai untuk filmstrip DAN hero preview; tambah extractor hero terpisah (maxWidth 720 q80, param injectable `previewFrameExtractor`).
  - Utang kosmetik: glow `feed_upload_bar.dart:524-548` (BoxShadow dalam ClipRRect — pindah ke wrapper luar); magic `76 + 28` `feed_post_preview_screen.dart:167,183` → konstanta bernama; dup oranye `feed_action_rail.dart:18` + `feed_product_anchor_card.dart:10` → `lib/features/feed/widgets/feed_colors.dart`.
  - Dead sweep tambahan (grep-verified): `feed_photo_upload_flow.dart` (1226 baris, 0 importer) DAN `feed_video_upload_flow.dart` (332 baris — `FeedPostSubmittedScreen` kini transitively dead karena satu-satunya pemanggil ada di file dead pertama). Route table `/member/postingan` di main.dart TETAP (dipakai route table).

### Keputusan sadar (final — jangan didebat ulang di task):
1. @mention TIDAK dibangun ulang (sudah ada) — hanya test regresi.
2. Picker preview video tetap MUTED by design (ala IG) — didokumentasikan dengan komentar.
3. Hardcode volume di feed_screen (preload/kontekstual) TIDAK disentuh — risiko regresi feed publik.
4. Tanpa Hero antar layar (media picker preview satu layar dengan grid; Hero lintas-route tidak sepadan) — premium via fade-through + haptics + badge pop.
5. Resume upload: dalam window authExpire (1 jam) → lanjut TUS tanpa re-provision; lewat window → re-provision (row FeedPost lama jadi orphan server-side — keterbatasan yang didokumentasikan jujur; TIDAK membangun endpoint cleanup server di fase ini).
6. Multi-draft maks **5 draft** (slot berlebih: yang terlama dihapus dengan konfirmasi implisit di UI "draft terlama akan terganti").

---

### Task 1: Utang perilaku 2A/2B

**Files:**
- Modify: `flutter_app/lib/state/feed_upload_store.dart` (cancel-mid-compress)
- Modify: `flutter_app/lib/screens/feed_post/feed_video_edit_screen.dart` (60.x detik)
- Modify: `flutter_app/lib/screens/feed_media_picker_screen.dart` (format-tak-didukung)
- Modify: `flutter_app/lib/screens/feed_post/feed_cover_picker_screen.dart` (hero preview hi-res)
- Test: `flutter_app/test/feed_upload_store_test.dart` (tambah), `flutter_app/test/feed_video_edit_screen_test.dart` (tambah), `flutter_app/test/feed_cover_picker_screen_test.dart` (tambah)

**Interfaces:** `FeedCoverPickerScreen` mendapat param opsional baru `previewFrameExtractor` (signature sama `frameExtractor`) — dipakai hero preview; default `VideoThumbnail.thumbnailData maxWidth 720 quality 80`.

- [ ] **Step 1 (test dulu — cancel):** tambah test di `feed_upload_store_test.dart`:

```dart
  test('cancelActive saat kompresi trimmed → status CANCELLED, bukan failed',
      () async {
    final tmp = await File(
      '${Directory.systemTemp.path}/store-cancel-${DateTime.now().microsecondsSinceEpoch}.mp4',
    ).create();
    addTearDown(() => tmp.delete());
    final store = FeedUploadStore.instance;
    store.clear();
    final started = Completer<void>();
    final blocker = Completer<MediaInfo?>();
    store.gate = VideoCompressGate(
      compressRunner: (path, {quality = VideoQuality.Res1280x720Quality,
          includeAudio = true, startTime, duration}) {
        started.complete();
        return blocker.future;
      },
      cancelRunner: () async =>
          blocker.completeError(StateError('cancelled by user')),
      isPluginBusy: () => false,
      resetPluginFlag: () {},
    );
    unawaited(store.startVideoUpload(
      draft: FeedCreatePostDraft(
        localVideoPath: tmp.path,
        originalDuration: const Duration(seconds: 70),
        trimStart: const Duration(seconds: 5),
        trimmedDuration: const Duration(seconds: 60),
      ),
    ));
    await started.future;
    await store.cancelActive();
    for (var i = 0; i < 50; i++) {
      final s = store.activeTask?.status;
      if (s == FeedUploadStatus.cancelled || s == FeedUploadStatus.failed || store.activeTask == null) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Status TIDAK boleh failed; boleh cancelled atau task sudah di-clear.
    expect(store.activeTask?.status, isNot(FeedUploadStatus.failed));
    store.clear();
  });
```

- [ ] **Step 2: fail → fix cancel.** Ubah `feed_upload_store.dart` catch kompresi (± :385): `if (range.startTimeSec != null && !_cancelRequested) rethrow;` + komentar: cancel yang membuat compress throw BUKAN kegagalan — jatuhkan ke `_checkCancel()` di bawah supaya transisi `cancelled`. Run → pass.

- [ ] **Step 3 (test dulu — 60.x):** tambah test di `feed_video_edit_screen_test.dart`:

```dart
  testWidgets('durasi 60.5s dianggap >60s: timeline langsung tampil',
      (tester) async {
    const d = FeedCreatePostDraft(
      localVideoPath: '/nonexistent/v.mp4',
      originalDuration: Duration(milliseconds: 60500),
    );
    await tester.pumpWidget(const MaterialApp(home: FeedVideoEditScreen(draft: d)));
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Geser pegangan untuk memangkas video'), findsOneWidget);
  });
```

- [ ] **Step 4: fail → fix 60.x.** `feed_video_edit_screen.dart:70` → `_showTimeline = _duration.inMilliseconds > _maxEditVideoSeconds * 1000;` dan `isFullRange` (:300-301) → `selectedSeconds * 1000 >= _duration.inMilliseconds` (full-range hanya bila seleksi menutup durasi PENUH; klip 60.5s dgn seleksi 60s → bukan full range → trimmed). Run → pass.

- [ ] **Step 5: format-tak-didukung di picker.** `_ensureVideoController` catch: set `String? _previewVideoError = 'Format video ini belum didukung. Coba video lain atau rekam ulang dengan kamera.';` (reset saat ganti asset) + `_showToast(_previewVideoError!)` sekali; `_buildPreviewContent` cabang `!ready && _previewVideoError != null` → tampilkan pesan inline (ikon `videocam_off_rounded` + teks muted center) alih-alih spinner selamanya. `_selectVideo` catch: bila error bukan String (bukan pesan durasi) → toast pesan format yang sama.

- [ ] **Step 6: hero preview hi-res sampul.** `feed_cover_picker_screen.dart`: tambah `final Future<Uint8List?> Function(String, int)? previewFrameExtractor;` — `_onDragEnd`/init hero preview pakai extractor ini (default maxWidth 720 q80), filmstrip tetap 120/50. Test: extend test existing — inject `previewFrameExtractor` yang mencatat pemanggilan, assert hero memakai extractor baru (bukan filmstrip extractor) setelah drag.

- [ ] **Step 7: analyze + full test + commit.**
```bash
git add -A flutter_app/lib flutter_app/test
git commit -m "fix(feed): utang perilaku — cancel-mid-compress=cancelled, klip 60.x wajib trim, pesan format-tak-didukung, sampul hero hi-res"
```

---

### Task 2: Utang kosmetik + dead sweep final

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_upload_bar.dart` (glow), `feed_action_rail.dart` + `feed_product_anchor_card.dart` (oranye)
- Create: `flutter_app/lib/features/feed/widgets/feed_colors.dart`
- Modify: `flutter_app/lib/screens/feed_post/feed_post_preview_screen.dart` (magic 76)
- Delete: `flutter_app/lib/screens/feed_photo_upload_flow.dart` (1226 baris), `flutter_app/lib/screens/feed_video_upload_flow.dart` (332 baris)

- [ ] **Step 1: glow.** Pindahkan BoxShadow glow keluar `ClipRRect` (:524-548): bungkus track dengan Stack — layer glow (Container tinggi 4, width fraksional sama, decoration shadow biru blur 6, TANPA clip) DI BAWAH `ClipRRect` track; atau shadow di wrapper `Container` luar. Visual: glow terlihat keluar 4px bar.
- [ ] **Step 2: oranye.** Buat `feed_colors.dart`: `const feedCommerceOrange = Color(0xFFFF7A00);` + doc; kedua file widget pakai konstanta bersama, hapus dup lokal + komentar stale.
- [ ] **Step 3: magic 76.** `feed_post_preview_screen.dart`: `const _previewBottomBarHeight = 76.0; const _previewOverlayGap = 28.0;` — dua Positioned pakai konstanta.
- [ ] **Step 4: dead sweep.** Grep-verifikasi 0 importer untuk kedua file → hapus keduanya. Grep sisa `FeedPostSubmittedScreen|FeedPhotoPickerScreen|FeedPhotoPreviewScreen|FeedPhotoDetailScreen|FeedPhotoUploadProgressScreen` di lib/ = 0. analyze berulang untuk orphan.
- [ ] **Step 5: analyze + full test + commit.**
```bash
git add -A flutter_app/lib
git commit -m "chore(feed): utang kosmetik (glow, konstanta, oranye bersama) + hapus 1558 baris dead code terakhir"
```

---

### Task 3: Draft sungguhan — daftar ber-thumbnail + restore video (2C-1)

**Files:**
- Create: `flutter_app/lib/state/feed_draft_store.dart`
- Modify: `flutter_app/lib/screens/feed_new_post_screen.dart` (`_saveDraftAndExit` → store)
- Modify: `flutter_app/lib/screens/member_posts_screen.dart` (loader + UI daftar + restore video)
- Test: `flutter_app/test/feed_draft_store_test.dart`

**Interfaces:**

```dart
/// Satu draft tersimpan. JSON round-trip stabil.
class FeedDraft {
  final String id;                 // 'draft-<epochMs>'
  final String type;               // 'video' | 'image'
  final String caption;
  final List<String> productIds;
  final List<String> mediaPaths;   // video: [finalVideoPath]; image: semua foto
  final String? thumbnailPath;
  final int? trimStartMs;
  final int? trimmedDurationMs;
  final int? originalDurationMs; // wajib utk rekonstruksi video draft (validasi 1..60s + trim guard)
  final bool userPickedCover;
  final int savedAtMs;
  // fromJson/toJson manual (pola model lain)
}

/// Repository daftar draft — key 'natalo-feed-drafts' (JSON array), maks 5
/// (terlama tergeser). Migrasi otomatis dari slot lama
/// 'natalo-feed-upload-pending' (format 'local|post-new|json|ts') saat load
/// pertama: parse → masukkan ke daftar → hapus key lama.
class FeedDraftStore {
  Future<List<FeedDraft>> load();          // validasi File.exists tiap media;
                                            // media hilang → draft ditandai rusak
                                            // (field runtime `broken`) tapi TETAP
                                            // dikembalikan supaya UI bisa tawarkan hapus
  Future<void> save(FeedDraft draft);       // upsert by id, trim ke 5
  Future<void> remove(String id);
  Future<void> clearAll();
}
final feedDraftStore = FeedDraftStore();
```

- [ ] **Step 1 (test dulu):** `feed_draft_store_test.dart` — kasus: save+load round-trip semua field; upsert by id; maks 5 (ke-6 → terlama hilang); migrasi key lama (seed prefs `natalo-feed-upload-pending` format lama → load → muncul di daftar + key lama terhapus); media hilang → draft `broken=true`; remove.
- [ ] **Step 2: fail → implement store.**
- [ ] **Step 3: layar Bagikan.** `_saveDraftAndExit` → `feedDraftStore.save(FeedDraft(...))`; id draft di-keep di state (`String? _draftId` — bila layar dibuka dari restore, pakai id sama supaya upsert bukan duplikat; param baru opsional `resumeDraftId` di `FeedNewPostScreen`). Setelah publish sukses (`_upload` sukses memicu `_goHome`) → `feedDraftStore.remove(_draftId!)` bila ada (fire-and-forget sebelum `_goHome`).
- [ ] **Step 4: Postingan Saya.** Ganti banner tunggal: `_loadLocalDrafts` → `feedDraftStore.load()`; bila >0 render **bagian "Draft"**: header kecil "Draft (n)" + rail horizontal kartu draft (thumbnail 72×96 radius 12 dari `thumbnailPath`/foto pertama via Image.file+errorBuilder, badge tipe `videocam/photo` + "x foto", umur relatif "2 jam lalu", tombol × hapus per kartu dengan konfirmasi kecil; draft `broken` → overlay ikon rusak + tap = tawarkan hapus). Tap kartu sehat → restore:
  - `image` → pola existing (`NewPostMediaDraft.photos(files)`, prefilled caption/productIds, + `resumeDraftId`).
  - `video` (HAPUS skip hardcoded :270) → rekonstruksi `FeedCreatePostDraft(localVideoPath: mediaPaths.first, thumbnailPath:, trimStart: trimStartMs→Duration?, trimmedDuration: null /*finalDuration fallback originalDuration*/, userPickedCover:)` — CATATAN: `originalDuration` tidak tersimpan → tambahkan field `originalDurationMs` ke payload FeedDraft DAN ke `_saveDraftAndExit` (dari `_videoDraft?.originalDuration`), pakai saat rekonstruksi (dibutuhkan validasi `_upload` 1..60s dan trim guard). `trimmedDuration` juga disimpan (`trimmedDurationMs`). Push `FeedNewPostScreen(draft: NewPostMediaDraft.video(rekonstruksi), prefilledCaption:, prefilledProductIds:, resumeDraftId:)`.
- [ ] **Step 5: analyze + full test + commit.**
```bash
git add -A flutter_app/lib flutter_app/test
git commit -m "feat(feed): draft sungguhan — daftar maks 5 ber-thumbnail di Postingan Saya, migrasi slot lama, restore video (tutup skip hardcoded)"
```

---

### Task 4: Resume upload setelah app ditutup (2C-2)

**Files:**
- Modify: `flutter_app/lib/state/feed_upload_store.dart` (persist + restore + resume)
- Modify: `flutter_app/lib/features/feed/widgets/feed_upload_bar.dart` (state "Lanjutkan upload?")
- Modify: `flutter_app/lib/screens/home_screen.dart` (panggil check saat initState post-frame)
- Test: `flutter_app/test/feed_upload_store_test.dart` (tambah)

**Interfaces:**

```dart
// FeedUploadStore tambahan:
static const _pendingKey = 'natalo-feed-upload-inflight';
/// Dipanggil sekali saat cold start (HomeScreen post-frame). Bila ada task
/// inflight tersimpan + file media masih ada → set _task status
/// `resumable` (enum baru) supaya FeedUploadBar menawarkan lanjut.
Future<void> checkForResumableUpload();
/// User tap "Lanjutkan": jalankan ulang pipeline. Video: bila provision
/// tersimpan masih dalam window authExpire → skip provisionUpload, langsung
/// TUS dgn credentials tersimpan (fingerprint TUS = path file yang sama →
/// resume byte); bila kadaluarsa → re-provision (row lama orphan server —
/// keterbatasan didokumentasikan). Foto: mulai ulang dari awal (murah).
Future<void> resumePersisted();
void dismissResumable(); // buang state + hapus persist
```
Persist JSON (`_pendingKey`): {localId, kind, caption, productIds, mediaPaths, thumbnailPath, videoDraft fields (localVideoPath/trimStartMs/trimmedDurationMs/originalDurationMs/userPickedCover/mimeType/originalFilename), provision {postId, videoGuid, tus{endpoint,videoId,libraryId,authSignature,authExpire}} | null, savedAtMs}. Ditulis saat `_runVideoUpload`/`_runPhotoUpload` MULAI + di-update setelah provision sukses. DIHAPUS di SEMUA jalur terminal — sukses, waitingReview, cancelled, DAN failed (retry failed sudah dilayani relay in-memory; persist semata untuk kasus app-kill saat preparing/uploading) — serta saat resumable di-dismiss.
Enum `FeedUploadStatus` tambah `resumable`.

- [ ] **Step 1 (test dulu):** tambah di `feed_upload_store_test.dart` — (a) `checkForResumableUpload` dengan prefs berisi payload valid + file temp ada → `activeTask.status == resumable` (kind/caption benar); (b) file media hilang → tidak ada task + persist terhapus; (c) `dismissResumable` → task null + persist terhapus; (d) persist ditulis saat upload mulai: jalankan `startVideoUpload` dgn gate yang menggantung (Completer) → cek `prefs.getString(_pendingKey) != null` → `clear()`.
- [ ] **Step 2: fail → implement store** per interface. `BunnyTusCredentials`/`BunnyUploadProvision` butuh `toJson` (tambahkan di `bunny_upload_service.dart`, mirror `fromJson`). `resumePersisted` video: rekonstruksi draft → jalur `_runVideoUpload` dengan flag `resumeProvision` (skip provision bila `authExpire * 1000 > now + 60_000` margin); kompresi: bila file hasil kompres sebelumnya tidak diketahui (tidak dipersist) → kompres ulang via gate (aman — gate idempoten secara efek).
- [ ] **Step 3: FeedUploadBar** state `resumable`: thumbnail existing + teks "Uploadmu kemarin belum selesai" (atau "…tadi belum selesai" — pilih satu, konsisten) + dua aksi kecil: pill biru "Lanjutkan" → `resumePersisted()`, × → `dismissResumable()`. Tanpa progress bar di state ini.
- [ ] **Step 4: HomeScreen** initState post-frame: `unawaited(feedUploadStore.checkForResumableUpload());` (idempotent — guard internal sekali per proses).
- [ ] **Step 5: analyze + full test + commit.**
```bash
git add -A flutter_app/lib flutter_app/test
git commit -m "feat(feed): resume upload setelah app ditutup — persist inflight + provision, bar 'Lanjutkan upload?', TUS lanjut byte terakhir dalam window 1 jam"
```

---

### Task 5: Carousel — urutkan & hapus slide (2C-3)

**Files:**
- Modify: `flutter_app/lib/screens/feed_new_post_screen.dart`
- Test: `flutter_app/test/feed_new_post_screen_test.dart` (tambah)

- [ ] **Step 1 (test dulu):** test dengan 3 foto dummy (File temp nyata berisi byte kecil supaya Image.file errorBuilder jalan): (a) strip slide tampil saat carousel (ada 3 item ber-key `ValueKey('slide-0..2')`); (b) tombol hapus slide mengurangi jumlah (counter jadi "1/2"); (c) hapus sampai 1 → tombol hapus hilang (min 1).
- [ ] **Step 2: fail → implement.**
  - State mutable: `late List<File> _photoFiles = List.of(widget.draft.photoFiles);` — SEMUA referensi `widget.draft.photoFiles` di state (thumbnail PageView, counter, dots, `_upload` :361, `_hasProgress`, `_saveDraftAndExit`, analytics type discriminator) pindah ke `_photoFiles`.
  - UI: di bawah blok thumbnail (hanya carousel >1 foto): strip slide horizontal `ReorderableListView` (scrollDirection horizontal, tinggi 76; item 56×72 radius 10 `Image.file` + badge nomor kecil + tombol × 18px pojok; `buildDefaultDragHandles: false` + `ReorderableDragStartListener` long-press) — reorder → `setState` pindahkan item + `_photoPageController.jumpToPage(clamp)`; hapus → konfirmasi ringan (snackbar undo TIDAK perlu — langsung hapus, min 1 tersisa; clamp `_photoIndex`).
  - Haptics: `AppHaptics.selection()` saat reorder drop & hapus.
- [ ] **Step 3: analyze + full test + commit.**
```bash
git add -A flutter_app/lib flutter_app/test
git commit -m "feat(feed): carousel — urutkan (drag) & hapus slide di layar Bagikan, min 1 foto"
```

---

### Task 6: Micro-interactions + sinkronisasi mute + test regresi mention (2C-5, 2C-6, 2C-4)

**Files:**
- Create: `flutter_app/lib/utils/fade_route.dart`
- Modify: push flow post — `feed_media_picker_screen.dart` (→ editor/Bagikan), `feed_post/feed_video_edit_screen.dart` (→ Bagikan, → cover), `feed_new_post_screen.dart` (→ preview, → cover)
- Modify: `flutter_app/lib/screens/feed_media_picker_screen.dart` (badge pop-in)
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart` (mute sync)
- Test: `flutter_app/test/mention_picker_test.dart` (baru), `flutter_app/test/fade_route_test.dart` (baru)

- [ ] **Step 1: util fade-through.** Ekstrak pola caption editor jadi:
```dart
/// Route fade-through premium untuk flow posting (pola sama dgn
/// showCaptionEditModal). Non-opaque optional.
Route<T> fadeThroughRoute<T>(Widget page, {bool fullscreenDialog = false}) =>
    PageRouteBuilder<T>(
      fullscreenDialog: fullscreenDialog,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
```
Test kecil: push via fadeThroughRoute → halaman muncul; pop → kembali (pumpWidget + Navigator).
Adopsi di 5 push flow post (picker→editor, picker→Bagikan, editor→Bagikan, Bagikan→preview, Bagikan/editor→cover) — ganti `MaterialPageRoute`; `fullscreenDialog` dipertahankan di preview. `showCaptionEditModal` TIDAK diubah (sudah fade sendiri).
- [ ] **Step 2: badge pop-in picker.** Badge nomor seleksi (`_SelectionBadge`): bungkus `AnimatedScale`/`TweenAnimationBuilder` scale 0.6→1.0 (180ms, `Curves.easeOutBack`) saat pertama muncul; `AppHaptics.selection()` saat foto terpilih (cek belum ada — kalau `AppHaptics.tap()` sudah ada di `_onTapAsset`, cukup itu, jangan dobel).
- [ ] **Step 3: mute sync member_post_detail.** Baca konteks `:1891,:1944,:2083,:2117` — pastikan `_muted` di-INIT dari `appSettingsStore.feedMuted` dan toggle user WRITE-BACK via `setFeedMuted` (pola sama feed_screen :2947); `setVolume(1)` hardcode `:2083` → `setVolume(appSettingsStore.feedMuted ? 0 : 1)` bila konteksnya init/resume playback (baca dulu — bila konteksnya "user tap unmute" biarkan tapi pastikan write-back). Tambahkan komentar keputusan di picker `:513` (muted by design ala IG).
- [ ] **Step 4: test regresi mention (2C-4 — fitur sudah ada).** `mention_picker_test.dart` unit murni `MentionPickerController` dengan `apiClient` di-mock? — cek testability: kalau `apiClient` global tak bisa di-inject, test hanya `_detectMention` behavior via public API (set text+selection → `isActive`/query benar; email `a@b.com` TIDAK aktif; `insertMention` mengganti `@par` → `@username `). Kalau perlu seam kecil `@visibleForTesting searchFn` di controller, tambahkan.
- [ ] **Step 5: analyze + full test + commit.**
```bash
git add -A flutter_app/lib flutter_app/test
git commit -m "feat(feed): fade-through route flow post, badge pop-in, mute sync member detail, test regresi mention"
```

---

### Task 7: Regression penuh + checklist device-verify 2C

**Files:** tidak ada perubahan kode.

- [ ] **Step 1: Full suite.** `cd flutter_app && flutter analyze && flutter test` — analyze hanya lint pre-existing; semua test pass.
- [ ] **Step 2: Checklist device-verify 2C (laporkan — JANGAN klaim terverifikasi):**
1. Batal upload saat kompresi video ter-trim → bar hilang bersih (status batal, BUKAN "Gagal mengunggah").
2. Video 60.5 detik → timeline trim langsung tampil, wajib potong.
3. Pilih file video korup/codec aneh → pesan "Format video ini belum didukung…" (bukan spinner selamanya).
4. Ubah Sampul: preview besar tajam (bukan blur 120px).
5. Draft: simpan video + foto → muncul di bagian Draft Postingan Saya ber-thumbnail → tap video draft → semua ter-restore (caption, produk, trim, sampul) → publish → draft hilang. Draft ke-6 menggeser terlama. Hapus file media manual → draft ditandai rusak, bisa dihapus.
6. Resume: mulai upload video besar → force-close app → buka lagi → bar "Lanjutkan upload?" → Lanjutkan → progress lanjut (dalam 1 jam: TUS resume dari byte terakhir — cek cepat selesai).
7. Carousel: drag urutkan slide + hapus slide → urutan di pratinjau & hasil post sesuai.
8. Transisi antar layar flow post = fade halus (bukan slide default), badge nomor pop-in, haptics terasa.
9. Suara di detail postingan member ikut setting mute feed dua arah.
10. Regresi cepat: flow lengkap video + carousel end-to-end tetap jalan; feed publik tak berubah.
