# Notifikasi — Lencana ❤️ Like + Format Komentar IG-style

**Date:** 2026-07-20
**Scope:** Client Flutter (`flutter_app/lib/screens/notifications_screen.dart`) + backend web (`lib/feed/activity-notifications.ts`)
**Status:** Draft for review
**Depends on:** Redesign notifikasi (#189), avatar/thumbnail polish (#200), ikon kategori (#201). Membangun di atas `_IdentityAvatar` + `StackedActorAvatars` + `_NotificationVisual`.

## Latar

Studi notifikasi Instagram (screenshot sinarpetstore) menunjukkan IG **hampir tidak memakai lencana** kecuali untuk **LIKE** (❤️ merah kecil di sudut foto). Komentar/tag/follow dibedakan lewat **teks + aksi inline**, bukan ikon. Dua gap paling cepat & berdampak vs app kita:

1. **Like belum ada lencana ❤️.** Notif like menampilkan foto aktor (atau avatar bertumpuk untuk agregat) tanpa penanda kategori. IG selalu menempelkan ❤️ merah kecil di sudut foto.
2. **Notif komentar bertele-tele.** Backend SUDAH menyertakan isi komentar (`activity-notifications.ts:88`: `"{actorName} mengomentari postingan '{judul}': {isi}"`), TAPI formatnya panjang: judul generik "Komentar baru di Feed kamu" + baris kedua menyebut judul post sebelum isi komentar → dibatasi 2 baris, isi komentar sering terpotong. IG ringkas: nama tebal → langsung isi komentar.

Fitur inline lain (tombol Follow-back, reply komentar dari notif) DIDESCOPE — spec terpisah nanti (lebih besar, butuh API baru).

## Feature A — Lencana ❤️ pada notif like (client-only)

**Berlaku HANYA untuk like** (`eventType == 'feed_new_like'`; mencakup like-post & like-komentar yang keduanya pakai eventType ini). Komentar/share/follow/mention TIDAK dapat lencana (sesuai IG).

**Aturan tampil (kunci kerapian): lencana hanya kita tambahkan di atas WAJAH asli.**
- Foto aktor (like tunggal berfoto) → foto + ❤️ badge (BARU).
- Avatar bertumpuk (like agregat, `actorAvatarUrls.length >= 2`) → tumpukan + ❤️ badge (BARU, satu badge di stack).
- **Tanpa foto → JANGAN sentuh.** KOREKSI (review): like tanpa foto TIDAK menampilkan "ikon hati penuh". Karena `_isBrandIdentity` = `_NotificationFilter.feed.matches || _isAnnouncement` dan judul like ("Feed kamu mendapat like baru"/"N orang menyukai…") mengandung kata feed/like → `brandIdentity == true`. Jadi hari ini like tanpa foto SUDAH merender **`OfficialBrandAvatar` (logo brand) + badge kategori ❤️** (dari `_NotificationVisual.from` feed_new_like → `favorite_rounded` `Color(0xFFE11D48)`, `_IdentityAvatar` cabang brandIdentity `:1104-1137`). Cukup — sudah ada hati kecilnya. Kita HANYA menambah badge di cabang foto + stacked; cabang brandIdentity dibiarkan apa adanya → tak ada risiko hati-dobel.

**Bentuk lencana:** lingkaran merah `Color(0xFFE11D48)` diameter 17, ikon `Icons.favorite_rounded` putih size 9, border putih (`colorScheme.surface`) width 2, `Positioned(right: -3, bottom: -3)` — identik struktur badge yang SUDAH ada di `_IdentityAvatar` (`notifications_screen.dart:1121-1135`, saat ini hanya untuk `brandIdentity`). Beri `key: ValueKey('notification-like-badge')` untuk test.

**Implementasi:**
- Tambah predikat kecil di `NotificationRow.build`: `final showLikeBadge = notification.eventType?.trim().toLowerCase() == 'feed_new_like';` — lalu teruskan ke widget avatar.
- `_IdentityAvatar`: tambah param `bool likeBadge = false`. Di cabang FOTO (`avatarUrl` non-empty, `:1086-1102`) — bungkus dengan `Stack` + badge ❤️ bila `likeBadge`. Cabang fallback ikon/brand TIDAK diberi badge (aturan di atas).
- `StackedActorAvatars`: tambah param `bool likeBadge = false`; render badge ❤️ overlay bila true (di atas Stack lingkaran, pojok kanan-bawah SizedBox 42).
- Badge widget di-ekstrak jadi helper kecil `_likeBadge(BuildContext)` (atau const widget) supaya tak duplikat markup di dua tempat.

**Brand-safety:** tak relevan (lencana statis, bukan identitas). Foto aktor sudah brand-safe dari plumbing sebelumnya.

## Feature B — Format komentar ringkas IG-style (backend-only)

**Ubah `sendCommentNotification`** (`lib/feed/activity-notifications.ts:82-100`):
- Ekstrak helper murni teruji `buildCommentNotificationText(actorName: string, content: string): { title: string; body: string }`:
  - `title = \`${actorName} berkomentar\`` — **WAJIB** memuat substring "komentar" (load-bearing, review #5): filter tab Feed (`_NotificationFilter.feed.matches`, `notifications_screen.dart:1243`) mencocokkan keyword `komentar`. "ber**komentar**" mengandung "komentar" → notif komentar tetap masuk tab Aktivitas/Feed. Jangan ganti "berkomentar" ke bentuk tanpa "komentar".
  - `body = truncateFeedText(content)` (util existing `notification-center.ts:76`, limit 80). Catatan (review #6, PRE-EXISTING, bukan regresi): `truncateFeedText` memotong per UTF-16 code-unit → bisa membelah emoji di batas 80 char. Perilaku ini sudah ada di kode komentar sekarang; helper mewarisinya, tak memperburuk. Di luar scope untuk difix di sini.
- Ganti `title: "Komentar baru di Feed kamu"` + `message: "${actorName} mengomentari postingan ...: ..."` menjadi hasil helper (`title`/`message` dari `buildCommentNotificationText(actorName, params.content)`).
- Baris notif jadi: **"Andi berkomentar** — Done ✅" (nama tebal jadi judul, isi komentar langsung; judul post dibuang karena thumbnail kanan sudah menunjukkan post-nya).

**Brand-safety:** `actorName` sudah brand-safe di builder (admin → `OFFICIAL_BRAND_NAME`, `:73-75`). Isi komentar = teks user biasa, aman ditampilkan (bukan identitas).

**Client:** TAK ada perubahan — baris sudah render "title — body" (`notifications_screen.dart` Text.rich). Isi komentar kini bagian menonjol.

**Di luar scope B:** notif balasan (`sendReplyNotification` `:152`) SUDAH menampilkan teks balasan; biarkan. Builder feed lain (like/share/mention/status) tetap format sekarang (opsi "rapikan semua" tidak dipilih).

## Testing

- **A (Flutter widget):**
  - like berfoto (`eventType:feed_new_like` + `actorAvatarUrl`) → `find.byKey(ValueKey('notification-like-badge'))` findsOneWidget.
  - like agregat (`actorAvatarUrls>=2`) → badge findsOneWidget (di atas stacked).
  - like tanpa foto → `notification-like-badge` findsNothing (cabang brandIdentity tak disentuh; logo brand + badge kategori existing tetap, tak dobel). Cukup verifikasi key baru tak muncul; JANGAN uji "ikon hati penuh" (tak pernah ada untuk like).
  - komentar (`eventType:feed_new_comment` + foto) → badge findsNothing (gate: bukan like).
- **B (backend unit `tsx --test`):** `buildCommentNotificationText('Andi', 'Done ✅')` → `title:'Andi berkomentar'`, `body:'Done ✅'`; isi panjang → body ter-truncate (`truncateFeedText`); nama brand admin diteruskan apa adanya (helper tak mengubah nama — brand-safety di call-site).

## Urutan Deploy

- **B** (backend): deploy → notif komentar BARU langsung ringkas. Notif lama tetap format lama (tak di-migrate). Tanpa migration.
- **A** (client): rilis app Flutter. App lama: like tetap tampil foto tanpa badge (degradasi anggun).
- Independen — bisa jalan terpisah.

## Acceptance Criteria

1. Notif like berfoto/agregat menampilkan lencana ❤️ merah (`notification-like-badge`) di sudut avatar; like tanpa foto tetap seperti sekarang (logo brand + badge kategori existing, tanpa badge kedua).
2. Komentar/share/follow/mention TIDAK mendapat lencana.
3. Notif komentar baru tampil ringkas: nama aktor (tebal) + isi komentar langsung, tanpa judul generik/judul-post; isi komentar tak lagi terpotong duluan.
4. Brand-safety terjaga: aktor admin → "Natalo Petshop Official" (tak bocor nama pemilik).
5. Perilaku non-terkait (routing tap, thumbnail, avatar bertumpuk, ikon kategori #201) tak berubah.
