# Edit Postingan — gaya IG "Edit info" + unifikasi alur edit — Design

## Latar belakang

Halaman Postingan (`member_post_detail_screen.dart`), tombol "..." → "Edit caption", membuka `_EditCaptionSheet`: bottom sheet sederhana (judul + subtitle peringatan + satu `TextField` berkotak/filled dengan `hintText` + tombol Batal/Simpan). Dibandingkan dengan layar "Edit info" Instagram (full-screen, header X/centang, caption menempel tanpa kotak, baris-baris section polos), tampilan kita terasa jauh lebih sederhana dan salah gaya.

Ditemukan saat eksplorasi: ada SATU LAGI layar edit post yang sudah dibangun lengkap — `MemberPostEditScreen` (`member_post_edit_screen.dart`), terdaftar sebagai route `/member/post-edit` di `main.dart:419` — tapi **tidak pernah dipanggil dari mana pun** di codebase (dead code). Layar ini punya cover thumbnail, caption editor, kartu kelola produk ditandai (`_TaggedProductsCard` + `_TaggedProductPickerSheet`), catatan review, tombol Simpan/Batal — tapi juga masih pakai gaya `TextField` berkotak (`filled: true`, `OutlineInputBorder`, `hintText`) yang sama masalahnya.

### Perbedaan nyata antara dua alur (diverifikasi dari kode)

`_EditCaptionSheet` path (`_editCaption()` di `member_post_detail_screen.dart:658-698`):
- Hanya edit **caption** — TIDAK bisa kelola produk ditandai.
- Panggil `apiClient.patchJson('/api/feed/posts/:id', {title, description})` langsung.
- **Sudah** sync ke `feedStore` via `feedStore.applyPostUpdate(updated)` (baris 692) — jadi bukan sync yang bermasalah.
- Optimistic status di `_withCaption()` (baris 1149-1156) **hardcode `status: 'PENDING_REVIEW'` tanpa syarat** — selalu anggap post balik ke review, bahkan untuk foto/carousel.

`MemberPostEditScreen._save()` (`member_post_edit_screen.dart:50-100`):
- Edit **caption + produk ditandai**.
- Panggil `feedService.updateMyPost(id, title, description, productIds)`.
- Sync ke `feedStore` via `applyPostUpdate` dengan `status: wasActive ? 'PENDING_REVIEW' : existing.status` — kondisional pada `wasActive`, tapi TIDAK membedakan video vs foto/carousel.
- Caption `maxLength: 280` (`_maxCaptionLength`), sedangkan `_EditCaptionSheet` `maxLength: 2000` — **beda 1720 karakter**.

### Sumber kebenaran status = BACKEND, bukan client (temuan kritis)

Status re-moderasi ditentukan **server-side**, bukan oleh payload client:
- `app/api/feed/posts/[id]/route.ts:562-565` (handler PATCH):
  ```ts
  // Customer edit re-trigger moderation — status ke PENDING_REVIEW.
  if (!isAdmin && post.status === "ACTIVE") {
    updates.status = "PENDING_REVIEW";
  }
  ```
  → reset **semua** customer ACTIVE post ke PENDING_REVIEW saat edit, **tanpa gate media type** (foto, carousel, video sama saja). Server mengabaikan apa pun status yang dikirim client.
- Backend saat ini juga TIDAK auto-approve foto/carousel saat CREATE (`app/api/feed/posts/route.ts:480`: `const status = isAdmin ? "ACTIVE" : "PENDING_REVIEW"`). Auto-approve foto/carousel = PR #168, **belum merge** (lihat memory "Feed auto-approve foto/carousel").

Konsekuensi: perubahan Flutter-saja (sembunyikan notice / jangan kirim PENDING_REVIEW untuk foto) akan membuat UI **berbohong** — post tetap balik ke review karena server yang memutuskan. Agar perilaku "foto/carousel tidak masuk review lagi saat di-edit" jadi NYATA, WAJIB ada perubahan **backend** pada edit path.

## Tujuan

1. Satu-satunya alur edit postingan di app ini adalah `MemberPostEditScreen` — dipakai dari titik masuk manapun; hapus `_EditCaptionSheet` dan seluruh alur bottom-sheet-nya (termasuk `_editCaption` PATCH manual + `_withCaption`).
2. Restyle `MemberPostEditScreen` mengikuti bahasa visual IG "Edit info": full-screen, header **X** (batal, kiri) + tombol **centang** bulat solid (simpan, kanan); caption `TextField` **tanpa kotak/placeholder-box** (borderless, menempel di sebelah cover thumbnail).
3. Baris "Produk ditandai" jadi baris list polos (label + ringkasan + chevron) bukan kartu tebal, tapi fungsi buka `_TaggedProductPickerSheet` dipertahankan.
4. **Backend (edit path)**: gate `[id]/route.ts:564` supaya customer ACTIVE post yang di-edit hanya direset ke PENDING_REVIEW kalau post itu **video** (`kind === "COMMUNITY"`); untuk foto/carousel (`kind === "PHOTO_CAROUSEL"`) status tetap `ACTIVE` (tidak re-moderasi).
5. **Flutter**: notice review + optimistic status reset di-gate ke video-only, cocok dengan keputusan server baru (poin 4), supaya UI optimistic tidak menyimpang dari kebenaran server.
6. **Caption limit**: naikkan `_maxCaptionLength` di `MemberPostEditScreen` dari 280 → **2000** supaya cocok dengan batas backend (`posts/route.ts:175` = 2000) dan tidak regres dari kapasitas `_EditCaptionSheet` lama (2000).

## Batas cakupan backend (penting — anti-collision)

- **HANYA** edit path (`app/api/feed/posts/[id]/route.ts:562-565`) yang diubah.
- **JANGAN** sentuh create path (`app/api/feed/posts/route.ts:480`) — auto-approve foto/carousel saat CREATE adalah domain PR #168 (belum merge); mengubahnya di sini akan tabrakan.
- Konsekuensi sadar: pra-#168, foto/carousel customer masih PENDING_REVIEW saat pertama dibuat (perlu approve admin sekali), tapi setelah ACTIVE, edit caption/produk-nya TIDAK lagi memicu review ulang. Ini kebijakan yang koheren ("sekali lolos, edit foto tidak perlu direview lagi") dan tidak bergantung pada #168.
- Kalau saat implementasi ditemukan PR #168 sudah menambah helper `lib/feed/post-moderation.ts` yang juga relevan untuk edit path, gunakan helper itu demi konsistensi; kalau belum ada (kondisi branch saat ini), inline cek `post.kind` langsung di PATCH handler.

## Arsitektur

### Backend — gate edit re-moderation ke video-only

- File: `app/api/feed/posts/[id]/route.ts`.
- `post` di query PATCH sudah `select: { kind: true, ... }` (baris ~346) — tidak perlu tambah field.
- Ganti blok baris 562-565:
  ```ts
  if (!isAdmin && post.status === "ACTIVE") {
    updates.status = "PENDING_REVIEW";
  }
  ```
  menjadi (gate pada kind; PHOTO_CAROUSEL = foto/carousel = trusted, tidak re-review):
  ```ts
  // Customer edit re-trigger moderation HANYA untuk video (kind COMMUNITY).
  // Foto/carousel (PHOTO_CAROUSEL) yang sudah ACTIVE tetap ACTIVE saat
  // di-edit — tidak perlu review ulang. Gate ini WAJIB sinkron dengan sisi
  // Flutter (MemberPostEditScreen: notice + optimistic status video-only).
  if (!isAdmin && post.status === "ACTIVE" && post.kind === "COMMUNITY") {
    updates.status = "PENDING_REVIEW";
  }
  ```
- Verifikasi saat implementasi: pastikan `kind === "COMMUNITY"` benar-benar berarti "video" untuk customer post (komentar file baris ~334-335 menyatakan "Community video lama pakai COMMUNITY, flow foto baru pakai PHOTO_CAROUSEL"). Kalau ada jalur customer video dengan kind lain, sesuaikan (mis. gate `post.kind !== "PHOTO_CAROUSEL"` sebagai "bukan foto → perlakukan sebagai perlu-review"). Pilih satu invarian eksplisit dan konsisten dengan Flutter.

### Entry point (unifikasi)

- `member_post_detail_screen.dart`: isi `_editCaption(int index)` diganti — bukan `showModalBottomSheet(_EditCaptionSheet)`, tapi:
  ```dart
  final changed = await Navigator.pushNamed(
    context,
    '/member/post-edit',
    arguments: post,
  );
  if (changed == true && mounted) {
    final synced = feedStore.get(post.id);
    if (synced != null) setState(() => _posts[index] = synced);
  }
  ```
  (`MemberPostEditScreen._save()` sudah `Navigator.pop(context, true)` + sudah `feedStore.applyPostUpdate` — jadi di sini cukup tarik ulang dari store, tidak PATCH lagi.)
- `_PostMenuSheet` (menu "...") tidak berubah — masih return `_PostMenuAction.edit`/`.delete`; hanya handler `.edit` yang berubah isi.
- Hapus total dari `member_post_detail_screen.dart`: class `_EditCaptionSheet` + `_EditCaptionSheetState` (~3121-3249) dan method `_withCaption` (~1149-1156) — keduanya tak terpakai lagi setelah perubahan ini. Verifikasi tak ada pemakai lain sebelum hapus.

### `MemberPostEditScreen` — header IG X/centang

- Buang `Scaffold.appBar` (AppBar title "Edit Postingan") dan buang tombol `FilledButton('Simpan Perubahan')` + `TextButton('Batal')` di bawah `ListView`.
- `Scaffold.body` jadi `Column`: baris header custom di atas + `Expanded(child: ListView(...))` konten.
- Header:
  ```dart
  Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      IconButton(icon: const Icon(Icons.close_rounded),
                 onPressed: _saving ? null : () => Navigator.pop(context)),
      Text('Edit info', style: TextStyle(fontSize: 16, fontWeight: NataloWeight.strong)),
      _SaveCheckButton(saving: _saving, onTap: _saving ? null : _save),
    ],
  )
  ```
- `_SaveCheckButton`: lingkaran solid diameter 32, `NataloColors.primary`, isi `Icon(Icons.check_rounded, color: Colors.white, size: 18)` saat idle; `SizedBox(16×16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))` saat `saving`. Judul "Edit info" (bukan "Edit Postingan") mengikuti label IG.

### `MemberPostEditScreen` — caption tanpa kotak

- Hapus label terpisah `Text('Caption', ...)` (baris 264-274).
- Susun cover thumbnail + caption dalam satu `Row` (thumbnail 56×56 rounded-8 kiri, `Expanded(TextField)` kanan) meniru IG.
- `TextField` caption:
  ```dart
  decoration: const InputDecoration(
    hintText: 'Tulis caption...',
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    filled: false,
    contentPadding: EdgeInsets.zero,
    isDense: true,
    counterText: '', // sembunyikan counter bawaan maxLength, ala IG
  ),
  ```
  `maxLength: _maxCaptionLength` dengan `_maxCaptionLength = 2000` (naik dari 280 — poin Tujuan 6). `minLines: 3`, `maxLines` boleh dinaikkan (mis. 8) supaya area tulis nyaman; tidak kritikal.
- Teks "Video/Media tidak bisa diganti..." tetap ada tapi dipindah jadi caption kecil di bawah seluruh card konten (bukan langsung di bawah thumbnail).

### `MemberPostEditScreen` — baris "Produk ditandai"

- Ganti `_TaggedProductsCard` (Container border tebal) jadi row datar dipisah `Divider(height: 1, color: cs.outlineVariant)`:
  ```dart
  InkWell(
    onTap: _saving ? null : _openProductPicker,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Produk ditandai', style: ...),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_selectedProductIds.isEmpty ? 'Tambah' : '${_selectedProductIds.length} dipilih',
                 style: TextStyle(color: cs.onSurfaceVariant, ...)),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ]),
        ],
      ),
    ),
  )
  ```
- Fungsi tidak berubah: `_openProductPicker()` → `_TaggedProductPickerSheet` yang sudah ada, TIDAK dibangun ulang.
- `_TaggedProductsCard` class dihapus kalau tak dipakai lagi. Kalau `_TaggedProductsCard` sebelumnya menampilkan preview foto/nama produk terpilih, preview itu cukup dilihat di dalam `_TaggedProductPickerSheet` (yang sudah render list) — tidak perlu direplikasi di row utama (IG "Add product details" juga cuma baris ringkas + chevron).

### `MemberPostEditScreen` — notice review + optimistic status video-only

- Kondisi render notice (baris 297):
  ```dart
  if (widget.post.statusInfo == FeedPostStatus.active && widget.post.isVideo)
  ```
  (foto/carousel: notice tidak render sama sekali.)
- Di `_save()` (baris 62-72), optimistic status untuk `feedStore.applyPostUpdate`:
  ```dart
  final needsReview = wasActive && widget.post.isVideo;
  ...
  status: needsReview ? 'PENDING_REVIEW' : existing.status,
  ```
  — ini memprediksi keputusan server baru (poin backend). WAJIB: Flutter `widget.post.isVideo` (`contentType == FeedContentType.video`) harus merepresentasikan post yang sama dengan `kind === "COMMUNITY"` di server. Verifikasi mapping ini saat implementasi (post video customer: client `isVideo == true` ↔ server `kind == "COMMUNITY"`). Kalau tidak konsisten, samakan invarian di kedua sisi sebelum lanjut.
- Toast setelah simpan: "Perubahan tersimpan. Postingan masuk review ulang." hanya kalau `needsReview`; selain itu "Perubahan tersimpan."

## Testing

### Backend
- Test unit/integration untuk PATCH `[id]/route.ts`:
  - Customer edit post `kind: "COMMUNITY"` (video) berstatus ACTIVE → status jadi PENDING_REVIEW.
  - Customer edit post `kind: "PHOTO_CAROUSEL"` (foto) berstatus ACTIVE → status **tetap** ACTIVE.
  - Admin edit → status tidak berubah (regression check, perilaku lama).
  - Ikuti pola test backend yang sudah ada untuk endpoint ini (cari test terkait `feed/posts` di `tests/` atau `app/api/feed/posts/**/__tests__`); kalau belum ada test PATCH, tambahkan yang minimal menutup tiga kasus di atas.

### Flutter
- Widget test `MemberPostEditScreen`:
  - Header punya ikon X + tombol centang bulat (bukan AppBar title lama, bukan tombol Simpan Perubahan/Batal bawah).
  - Tap X → `Navigator.pop` tanpa memanggil save.
  - Tap centang → memicu `_save()` (verifikasi via state `_saving`/interaksi service).
  - Caption `TextField` border-less (`InputDecoration.border == InputBorder.none`), tanpa fill.
  - `maxLength` caption = 2000 (regression guard vs 280).
  - Baris "Produk ditandai" tampil sebagai row + tap memicu `_openProductPicker`.
  - Notice review: render untuk `isVideo && active`; TIDAK render untuk foto/carousel meski active.
  - `_save()` optimistic status: video active → `PENDING_REVIEW`; foto/carousel active → `existing.status`.
- `member_post_detail_screen.dart`: `_editCaption(index)` sekarang memicu `Navigator.pushNamed('/member/post-edit', arguments: post)` — tambah test yang memverifikasi navigasi ini (route + arguments benar), gantikan ekspektasi lama soal bottom sheet.
- **Catatan test existing**: TIDAK ada test yang menguji `_EditCaptionSheet` (sudah dicek). `member_post_detail_screen_caption_test.dart` menguji **tampilan** caption (expand/"selengkapnya"), TIDAK terpengaruh penghapusan sheet — jangan diubah kecuali gagal kompilasi karena simbol yang dihapus.
- `flutter analyze` bersih; `flutter test` untuk file yang disentuh hijau.

## Yang TIDAK berubah (di luar cakupan)

- Create path backend (`posts/route.ts:480`) — domain PR #168, jangan disentuh.
- Endpoint/payload `feedService.updateMyPost` — struktur tidak berubah (server tetap yang memutuskan status; kita hanya mengubah ATURAN keputusan server di edit path).
- `_TaggedProductPickerSheet` — picker produk tidak di-redesign, cuma dipanggil dari row baru.
- Fitur IG "Edit info" yang tak relevan (Tag people, Add location, Add AI Label, Content funding) — TIDAK ditambahkan; cakupan hanya meniru bahasa visual, bukan replikasi section.
- Media (video/foto) tetap tidak bisa diganti — upload ulang required.
