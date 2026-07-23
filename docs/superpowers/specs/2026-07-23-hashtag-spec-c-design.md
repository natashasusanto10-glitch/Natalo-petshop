# Spec C — Hashtag di Caption ala Instagram

**Tanggal:** 2026-07-23
**Status:** Draft — menunggu review user
**Bagian dari:** rencana 5 bagian (A–E) mengganti tag belanja dengan Tag People + Hashtag + Lokasi. Spec A (PR #245) & Spec B (PR #250 + polish #252) sudah merged ke main.

## Tujuan

Hashtag `#kucing` di caption jadi tappable → membuka halaman hashtag berisi semua post ber-tag sama; composer memberi saran hashtag saat mengetik `#`. Greenfield total — belum ada parsing `#`, model DB, maupun search post apa pun.

Referensi perilaku: IG 2024–2026 (riset web): follow-hashtag sudah DIHAPUS IG (Des 2024); limit resmi kini **5 hashtag per post** (Des 2025); hashtag = alat klasifikasi/pencarian, bukan pendongkrak reach; case-insensitive, tanpa spasi. Arsitektur IG sendiri: Postgres + tabel hashtag ber-`media_count` + junction table — Pendekatan A di bawah adalah miniaturnya.

## Cakupan

**Masuk Spec C (paket inti):**
1. Hashtag tappable di caption feed & komentar (render).
2. Penyimpanan (tabel `Hashtag` + `FeedPostHashtag`) + parse server-side saat create post.
3. Halaman hashtag (grid post ber-tag, terbaru dulu).
4. Autocomplete `#` di editor caption composer.

**DILUAR cakupan:**
- Follow-hashtag (IG pun sudah menghapusnya).
- Tab "Teratas" di halaman hashtag — terbaru-saja (platform kecil, skor engagement belum bermakna).
- Hashtag di hasil pencarian akun/feed (search feed post belum ada sama sekali — spec lanjutan).
- Index hashtag dari KOMENTAR (komentar hanya render tappable; yang menentukan halaman hashtag hanya caption).
- Live-highlight biru saat MENGETIK di editor (mention pun saat ini tidak — keduanya jadi polish terpisah nanti, butuh custom `TextEditingController.buildTextSpan`).
- Trending/counter real-time ala IG.

## Keputusan produk (terkunci via diskusi)

- **Limit: 5 hashtag unik per post** (ikut IG terbaru; mention tetap 10 — beda limit disengaja).
- **Urutan halaman hashtag: terbaru saja** (grid tunggal).
- **Area: caption + komentar tappable; index caption saja.**
- **Arsitektur: A — tabel join penuh** (dikonfirmasi setelah cek arsitektur IG: Postgres, tabel hashtag ber-media_count, junction table).
- **Backend tetap Next.js + Prisma + Neon** — beban hashtag ringan (parse + query ber-index); mesin search khusus (Elasticsearch dkk.) baru relevan di skala jauh lebih besar, dan ditambahkan di samping, bukan mengganti.

## 1. Data & API

### Model Prisma (2 tabel baru)

- `Hashtag`: `id`, `name` (String, **unik, disimpan lowercase**), `postCount` (Int default 0), `createdAt`.
- `FeedPostHashtag`: `id`, `feedPostId` (FK → FeedPost, **onDelete: Cascade**), `hashtagId` (FK → Hashtag, Cascade), unik `(feedPostId, hashtagId)`, index `hashtagId`.
- **Migration file sungguhan + apply ke kedua database Neon — BUKAN `db push`** (insiden schema-drift product-video).
- Baris `Hashtag` ber-postCount 0 dibiarkan (tidak dihapus) — murah, hindari churn.

### Aturan parsing — SATU sumber aturan, mirror server ↔ client

- Regex: `#([a-z0-9_]+)` case-insensitive **dengan boundary**: `#` hanya valid jika didahului awal-teks atau whitespace. `harga#promo` dan URL `natalo.com/#promo` TIDAK menghasilkan tag. (Teknik bebas — lookbehind ATAU grup awal `(^|\s)` — asal hasilnya identik di server & Flutter.)
- Filter di fungsi extract (kedua sisi, ala `extractMentionHandles` yang filter 3–30): panjang nama **2–50**; duplikat dalam satu caption dihitung sekali; normalisasi **lowercase** untuk simpan/query.
- **Maks 5 hashtag unik per post** — server tolak `400` "Maksimal 5 hashtag per postingan". Composer memvalidasi hal yang sama sebelum submit (400 = jaring pengaman).
- Parse **server-side dari caption** (server sumber kebenaran; client TIDAK mengirim daftar tag terpisah), di **SEMUA jalur create post**: `POST /api/feed/posts` (foto client), `POST /api/feed/bunny/upload-url` (video client), **dan jalur create admin "Buat Post Feed"** (verifikasi route konkretnya saat planning — kalau admin pakai route terpisah, parse di sana juga; caption hasil AI generator tunduk aturan yang sama termasuk limit 5). Semua **dalam transaksi yang sama** dengan create post: upsert `Hashtag` by name → create junction → increment `postCount`.
- Hapus post (jalur delete existing): kalau hard-delete → cascade hapus junction + decrement `postCount`; kalau ternyata soft-delete (ubah status — verifikasi saat planning) → junction dibiarkan, aman karena halaman hashtag ter-filter status dan `postCount` memang aproksimatif.
- Edit caption belum ada di app → tidak ada pipeline re-index (catatan: kalau edit post dibuat kelak, wajib re-parse + diff junction).

### `postCount` = sinyal aproksimatif (keputusan sadar)

`postCount` TIDAK dijamin akurat (video tak pernah `ready`, moderasi menonaktifkan post, dsb. tidak men-decrement). Perannya HANYA urutan autocomplete (IG pun menampilkan angka aproksimatif). **Header halaman hashtag memakai hitungan sungguhan** dari query yang sama dengan grid — selalu konsisten dengan yang tampil.

### Endpoint baru

- `GET /api/feed/hashtags/[name]` → `{ name, postCount(akurat via query), posts[] }` + paginasi cursor.
  - **Validasi param `name`**: regex + panjang + lowercase yang sama; tidak lolos → `400`.
  - **Filter visibilitas = aturan feed** (status ACTIVE + video `encodingStatus: ready`) — junction video ditulis saat provision, post video baru MUNCUL di halaman hashtag setelah playable (pelajaran fix notif video Spec B, tanpa perlu defer-index).
  - **Serializer feed existing** — otomatis brand-safe (`lib/social/brand-user.ts`) + bawa `taggedUsers` dll.
- `GET /api/feed/hashtags/search?q=<prefix>` → maks 8 `{ name, postCount }`, urut `postCount` desc, prefix match lowercase. (`q` minimal 1 karakter.)
- Catatan teknis: prefix `LIKE 'abc%'` di Postgres collation default tidak selalu memakai btree index biasa — skala sekarang aman; kalau kelak lambat, solusinya index `text_pattern_ops` (dicatat di sini supaya tidak perlu riset ulang).

Tanpa notifikasi (hashtag tidak menandai siapa pun).

## 2. Composer — autocomplete `#`

Semua di **editor caption existing** (`feed_caption_edit_screen.dart`) — dipakai bersama jalur foto & video.

- Editor sudah punya `MentionPickerController` + overlay `MentionPicker` untuk `@`. Tambahkan padanan `#`: ketik `#` + huruf → debounce 300ms → `GET /api/feed/hashtags/search?q=` → overlay maks 8 baris.
- Baris saran: `#kucing` · "24 postingan" (postCount), urut desc.
- Tap saran → `#partial` diganti `#kucing` + spasi, kursor di belakangnya.
- Tanpa hasil → tanpa overlay; user bebas mengetik tag baru (tercipta implisit saat post terbit — tidak ada UI "buat tag").
- Struktur: `HashtagPicker` widget saudara `MentionPicker` (file terpisah `widgets/hashtag_picker.dart`) — dua trigger, dua sumber data, tidak digabung.
- **Validasi limit 5** tiga lapis, pesan sama persis "Maksimal 5 hashtag per postingan": (1) tombol Simpan editor diblokir + pesan inline merah; (2) submit post menghitung ulang; (3) server 400.
- Semua teks bahasa Indonesia.

## 3. Viewer & halaman hashtag

### Render tappable

- **Satu inti parser bersama** di `mention_text.dart` yang mengenali dua pola satu pass: `@mention` (existing, tap → `/u/<handle>`) + `#hashtag` (baru, tap → halaman hashtag). PENTING: `MentionText` (dipakai sheet komentar & detail post) adalah widget "self-managed recognizer" dengan jalur parse sendiri — inti parser baru WAJIB dipakai oleh `buildMentionSpans` DAN `MentionText`, supaya caption feed, komentar, dan detail post semuanya kebagian. Memperluas `buildMentionSpans` saja = komentar bolong.
- **Regex render = mirror persis extractor server** (boundary + panjang) — `natalo.com/#promo` tidak boleh biru.
- Style hashtag: biru sama mention (`0xFF0B7FEA`) tapi **w600** (token strong NataloWeight), bukan w800 mention — orang tegas, topik lebih ringan, tanpa warna baru.
- **Tap → navigasi dengan nama lowercase** (caption boleh menampilkan `#KucingLucu`, query pakai `kucinglucu`). Judul halaman menampilkan bentuk lowercase kanonik.

### Halaman hashtag

- Layar baru: judul `#kucing`, subjudul "N postingan" (hitungan akurat query — bukan `postCount`).
- Grid post 1:1 **reuse pola grid profil** — widget konkret ditentukan saat planning dengan memverifikasi apa yang benar-benar ada di main (JANGAN merujuk `GalleryPostTile`/`PostGalleryOpener` hasil ekstraksi Tersimpan — branch itu belum di-PR).
- **WAJIB multi-author**: post di halaman hashtag berasal dari banyak akun. Pembuka/viewer post wajib membawa author per-post (nama + avatar penulis masing-masing, brand-safe untuk official) — JANGAN reuse buta jalur galeri profil yang berasumsi satu author (jebakan yang sama pernah muncul di halaman Tersimpan).
- Filter visibilitas = aturan feed (§1). Paginasi cursor. 
- Empty state: "Belum ada postingan dengan tag ini."
- Tap hashtag dari post di dalam halaman hashtag → menumpuk halaman hashtag lagi (back stack normal, ala IG).

## 3b. Kualitas UI premium (WAJIB — pelajaran Spec B)

Spec B butuh dua PR polish susulan karena standar ini tidak tertulis di spec-nya. Untuk Spec C, semuanya requirement sejak awal:

- **Semantics** di setiap elemen interaktif baru: baris `HashtagPicker` ("Tag kucing, 24 postingan"), span hashtag (label "Tag kucing"), AppBar halaman hashtag.
- **Tap target**: baris picker ≥48dp (ListTile default lolos). Span hashtag inline text = pengecualian sadar (setinggi baris, sama seperti mention & IG) — dicatat, bukan dilanggar diam-diam.
- **Tap feedback**: elemen interaktif custom non-ListTile wajib pressed-state (pola `_PressableTag` dari feed_user_tag_pill.dart); ListTile sudah punya ripple bawaan.
- **Reduced-motion**: animasi baru APA PUN (kemunculan overlay picker dll.) lewat `MotionPrefs.effective(context, ...)` — konsisten fix #252.
- **State halaman hashtag**: error TIDAK boleh menyamar jadi empty state (bug app-wide yang sudah dibersihkan PR #46) — pakai error view + coba-lagi standar app; loading pakai pola grid existing; footer indikator paginasi.
- **Haptic**: pilih saran picker = haptic ringan, samakan dengan perilaku MentionPicker existing (verifikasi saat planning).
- **Kontras**: biru `0xFF0B7FEA` di atas putih ~3,9:1 (sedikit di bawah 4,5:1) — dipertahankan demi konsistensi dengan mention yang sudah memakainya; masuk daftar device-verify kontras BERSAMA mention (kalau diubah kelak, keduanya sekaligus).
- **Token**: warna/bobot dari NataloColors/NataloWeight — tanpa hex/angka lepas baru.

## 4. Testing

- **Backend**: extractor (boundary `harga#promo` & `/#promo` ditolak; panjang 2–50; dedup; lowercase; >5 → error), transaksi create (upsert + junction + increment; foto, video, DAN jalur admin), delete post (sesuai temuan hard/soft), endpoint page (visibilitas feed; multi-author brand-safe; hitungan akurat; param invalid → 400; cursor), autocomplete (prefix, urut postCount, maks 8, q kosong → list kosong tanpa error).
- **Flutter**: unit regex mirror (kasus identik dengan server), widget render caption DAN komentar/detail via `MentionText` (`#tag` biru w600 tappable; `@mention` tetap; `/#promo` tidak tappable; kombinasi mention+hashtag satu caption), halaman hashtag (grid multi-author, judul+hitungan, empty state), `HashtagPicker` (muncul saat `#`+huruf; tap sisip+spasi; tanpa hasil tanpa overlay), validasi limit 5 editor.
- Golden hanya bila layout berubah (kemungkinan tidak — reuse).

## Keputusan & trade-off tercatat

- Limit 5 (IG terbaru) ≠ limit mention 10 — disengaja, dua fitur beda fungsi.
- `postCount` aproksimatif; akurasi hanya di header halaman (query) — hindari pipeline sinkronisasi penuh yang overkill.
- Index caption saja; komentar hanya render — hindari pipeline index+cleanup di route komentar.
- Terbaru-saja tanpa tab Teratas; tanpa follow-hashtag; tanpa search feed; tanpa live-highlight editor — semua dicatat sebagai penundaan sadar, bukan kelupaan.
- Next.js + Prisma dipertahankan — beban fitur ringan; mesin search khusus belum relevan di skala ini.
