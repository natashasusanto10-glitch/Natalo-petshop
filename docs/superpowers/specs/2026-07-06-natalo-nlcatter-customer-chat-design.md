# Design Spec — Integrasi Chat Customer Natalo ↔ NLCATTER

- **Tanggal:** 2026-07-06
- **Status:** Draft desain (belum ada implementasi) · **Rev 2** (setelah review adversarial 5-lensa)
- **Repo terpengaruh:** `natalopetshopflutter/` (app customer Flutter + web/backend Next.js) dan `NLCHAT/` (app internal NLCATTER Flutter)

---

## 0. Ringkasan

Customer di **Natalo App** menekan ikon chat (ala e-commerce umum) dan mengobrol langsung dengan toko. Pesan **tidak** ke WhatsApp — masuk real-time ke **Customer Inbox di NLCATTER** (app internal staff), staff membalas, balasan tampil di Natalo App. Tanpa langkah "pilih topik". Bila dibuka dari halaman produk, konteks produk terbawa otomatis.

**MVP mencakup:** chat teks + foto dua arah, product-context otomatis, staff kirim product card, catatan internal, detail customer, status chat, push dua arah, pemisahan & keamanan data internal.

---

## 1. Temuan Audit (Phase 0) — yang mengubah premis brief

| Aspek | Natalo (customer) | NLCATTER (staff) |
|---|---|---|
| Project Firebase | `natalopetshop-818c4` | `tokochat-a8879` (**berbeda**) |
| Auth | Token API sendiri (email/pw + WA OTP) via Next.js — **bukan Firebase Auth** | Firebase Auth (email/pw) |
| Data utama | Next.js/Prisma/Postgres (REST) | Firestore |
| Pakai Firestore? | **Tidak** (Firebase hanya FCM/analytics/crashlytics) | Ya, intensif |
| Upload foto | **UploadThing** (review/produk/profil, via `lib/uploadthing` `uploadToUT` + `validateImageMagicBytes`); **Bunny CDN** hanya untuk video Feed — bukan Firebase Storage | Firebase Storage tokochat (`chat_images/{chatId}/`) |
| Cloud Functions | Tidak | 23 fungsi (Node 22): `notifyNewMessage`, `sendChatReply`, dll |
| State mgmt | ChangeNotifier singleton manual (tanpa paket `provider`) | Provider + StreamBuilder |
| Role | member (customer) | **hanya** `owner` / `karyawan` (tak ada CS/admin) |

**Konsekuensi kunci:** brief mengasumsikan satu Firestore bersama. Realitanya dua project terpisah, dan app customer **tidak memakai Firestore/Firebase Auth** (murni REST/Prisma, upload ke Bunny CDN). Semua data customer/order/produk hidup di sisi Next.js; NLCATTER adalah pulau Firebase terpisah. Karena itu dibutuhkan "jembatan" — lihat Topologi A.

---

## 2. Arsitektur — Topologi A (Proxy via Next.js)

**Sumber kebenaran:** koleksi `customerChats` di **Firestore tokochat**. App customer tetap REST; **backend Next.js jadi proxy** (service-account tokochat / Admin SDK) yang menulis ke tokochat *atas nama* customer. NLCATTER membaca/menulis native. Customer **tak pernah** punya identitas Firebase di tokochat.

```
Natalo App (REST, tanpa Firestore)
   │  POST /api/chat/* (sesi member Natalo, + clientMsgId)
   ▼
Next.js proxy ──(Admin SDK, service account tokochat)──►  Firestore tokochat
   ▲                                                        │  customerChats/{id}
   │  webhook + shared-secret (push balik)                  ▼  (realtime native)
Cloud Function tokochat ◄──────────────────────────────  NLCATTER (staff baca & balas)
   │
   ▼  FCM ke customer (kredensial project natalopetshop)
Natalo App (catch-up fetch saat buka + short-poll saat layar chat terbuka)
```

**Alur 1 pesan (customer → staff):**
1. Customer → `POST /api/chat/send` (terautentikasi sesi member Natalo; body memuat **`clientMsgId` (UUID)** untuk idempotensi).
2. Next.js verifikasi sesi → `memberId`; **transaksi** create-if-absent room `cust_<memberId>`; append message idempoten (no-op bila `clientMsgId` sudah ada); segarkan snapshot profil (merge).
3. CF tokochat `notifyNewCustomerMessage` → hitung penerima **server-side** (owner + `canHandleCustomer`), naikkan `unreadCount.{uid}` per penerima, kirim FCM ke token staff (di tokochat). NLCATTER menerima update **live**.
4. Staff balas di NLCATTER (native) → tulis ke Firestore tokochat; naikkan `unreadForCustomer`.
5. CF tokochat → **webhook (ber-shared-secret)** ke Next.js → Next.js resolve `customerId`→token FCM (dari Prisma) → **FCM ke customer** (kredensial natalopetshop). App customer melakukan **catch-up fetch** saat dibuka; saat layar chat terbuka juga short-poll ~3 dtk.

**Kenapa A (bukan B/C):** A menaruh kerumitan lintas-project di **server** (aman, service account), kedua app client tetap sesuai bentuknya, dan **rules internal NLCATTER tak disentuh** (customer tak pernah masuk project internal). B membebani kedua app (customer dapat stack Firestore/Auth; NLCATTER dual-project). C mewajibkan menulis ulang semua rules internal berbasis `isSignedIn()` — risiko tinggi, ditolak.

**Realtime:** staff = listener native (<0.5 dtk). Customer = FCM + catch-up/short-poll (~1–3 dtk saat layar terbuka; saat app tertutup bergantung FCM, sama seperti B).

---

## 3. Model Peran & Akses

- **Hanya dua role: `owner` dan `karyawan`.** "Admin"/"CS" = sebutan bisnis; teknis = `karyawan`.
- **Akses Customer Inbox** = `isOwner() || users.canHandleCustomer == true`. Field penanda di `users/{uid}`, di-set **hanya owner**. Bukan role baru.
- **Tanpa assignment.** Customer Inbox = **antrean bersama**; siapa pun yang berwenang menangani chat mana saja. Tidak ada `assignedStaffId`/routing.
- Semua staff penangan kapabilitas sama (balas, ubah status, catatan internal). Gradasi owner-only bisa ditambah belakangan.
- Ke customer, identitas pengirim selalu **"toko"** ("Natalo Petshop & Aquarium"), tak pernah nama/role staff. Di NLCATTER tampil nama orangnya.

---

## 4. Model Data (Firestore tokochat)

Koleksi **baru & terpisah** `customerChats` (bukan flag di `chats` internal) → rules & query berbeda, `chats` internal tak tersentuh. Tab "Customer" query `customerChats`; tab "Internal/Grup" tetap `chats`.

### 4.1 Skema

**`customerChats/{chatId}`** — `chatId = cust_<nataloMemberId>` (deterministik, 1 room/customer, idempoten):
```
customerId            // id member Natalo (Prisma), BUKAN uid Firebase
customerName, customerPhone            // snapshot Natalo
summary: { totalBelanja, orderCount, lastOrder:{inv,status,total} }  // snapshot Natalo
summaryUpdatedAt      // kapan snapshot diambil (indikator kesegaran)
status                // open | waiting_customer | waiting_staff | resolved
statusChangedBy, statusChangedAt       // audit
lastMessageText, lastMessageType, lastMessageAt, lastMessageSender   // customer|staff
unreadCount: { <staffUid>: int }       // per-staff (pola sama chat internal)
unreadForCustomer: int                 // skalar (hanya 1 principal customer)
lastContextProductId?                  // untuk de-dup product_context
source                // 'natalo_app'
createdAt, updatedAt
```

**`.../messages/{msgId}`**:
```
clientMsgId           // UUID dari client → idempotensi & rekonsiliasi optimistic
senderRole            // customer | staff
senderId              // id member Natalo (customer) | uid Firebase (staff)
senderName
type                  // text | image | product | product_context | system
text
image?: { url }       // URL apa adanya (lihat 4.3)
product?: { productId, slug, name, imageUrl, price, stock }
createdAt             // server timestamp (Admin SDK / native) — kunci urutan
status                // queued | sending | sent | failed  (optimistic UI)
readByStaffAt?, readByCustomerAt?
```
Tipe yang **boleh dibuat customer**: hanya `text` & `image`. `product`, `product_context`, `system` hanya staff/proxy.

**`.../internalNotes/{noteId}`** — subkoleksi terpisah, tak pernah ke customer:
```
authorId, authorName, text, createdAt   // immutable
```

### 4.2 Kepemilikan tulis, urutan & idempotensi
- **Proxy (customer) menulis HANYA**: `customerName/customerPhone/summary/summaryUpdatedAt/lastContextProductId` (merge), append `messages` customer, `lastMessage*` sisi customer, `unreadForCustomer` reset (saat customer fetch). Increment via `FieldValue.increment` — **bukan** read-modify-write.
- **NLCATTER (staff) menulis HANYA**: `status/statusChanged*`, append `messages` staff, `lastMessage*` sisi staff, `unreadCount.{uid}` reset (saat buka room).
- **CF menulis**: `unreadCount.{uid}` increment per penerima (saat pesan customer), `unreadForCustomer` increment (saat balasan staff).
- **Room create/restore**: proxy pakai **transaksi** (atau `set(..., {merge:true})` dgn `createdAt` hanya-jika-absent) → cegah double-init saat double-tap / dua device. Append pesan tak pernah menjalankan ulang inisialisasi room.
- **Urutan**: kunci `createdAt` server; klien rekonsiliasi bubble optimistic via `clientMsgId` (buang duplikat saat catch-up/poll). Karena tulisan customer (proxy) & staff (native) berasal dari dua jam berbeda, urutan tampilan mengacu `createdAt` server, bukan waktu lokal.

### 4.3 Storage gambar (keputusan eksplisit)
- **Customer → proxy → UploadThing** (reuse `uploadToUT` di `lib/uploadthing` + `validateImageMagicBytes`, persis pola `api/reviews/upload`). App customer mengunggah **bytes ke proxy** (bukan langsung ke CDN); proxy validasi lalu upload ke UploadThing dan simpan URL hasilnya di `image.url` → validasi terpusat di server. Endpoint `api/chat/send-image` praktis tiruan `api/reviews/upload` (session `CUSTOMER` + magic-byte + `uploadToUT`).
- **Staff → NLCATTER → Firebase Storage tokochat** (`customer_chat_images/{chatId}/`, tambah blok `storage.rules`). Download-URL bertoken → dapat dimuat app customer sebagai URL biasa (tetap di jalur native NLCATTER — least-change).
- Keduanya **hanya URL** di dokumen pesan → NLCATTER & Natalo tinggal me-render URL apa pun. Kontrol akses = **key tak-tertebak** (URL UploadThing publik-permanen tanpa ACL; didokumentasikan sebagai satu-satunya kontrol, tak ada PII sensitif diasumsikan privat; signed-URL = tahap lanjut). Validasi upload lihat §5.2.

### 4.4 Snapshot profil
Nama/telepon/`summary` = snapshot dari Prisma, ditulis proxy tiap customer berinteraksi; `summaryUpdatedAt` menandai kesegaran, ditampilkan di sheet detail ("terakhir diperbarui …"). NLCATTER tak pernah menyentuh DB Natalo.

---

## 5. Keamanan — dua lapis + auth server-to-server

### 5.1 Firestore rules (tokochat): staff-only
```
match /customerChats/{chatId} {
  function canCS() { return isSignedIn() && (isOwner()
    || get(/databases/$(database)/documents/users/$(request.auth.uid))
         .data.get('canHandleCustomer', false) == true); }
  allow read, list, create, update: if canCS();   // list mengandalkan canCS() atas users doc pemanggil
  allow delete: if false;
  match /messages/{m}      { allow read, create, update: if canCS(); allow delete: if false; }
  match /internalNotes/{n} { allow read, create: if canCS(); allow update, delete: if false; }
}
```
Query tab Customer: `where status in [open,waiting_customer,waiting_staff] orderBy lastMessageAt desc limit N` (index §12). Karyawan tanpa `canHandleCustomer` → `list` ditolak rules (bukan tampil kosong; diuji di emulator).

### 5.2 Proxy Next.js: authz sisi customer
- **Sesi member Natalo** diverifikasi memakai mekanisme auth Natalo yang sudah ada (middleware/cookie/bearer `getSession('CUSTOMER')`), menghasilkan `memberId` (String, = `member_profile.id`).
- Paksa `chatId == cust_<memberId>` (tak bisa akses chat lain).
- **Fetch pakai projeksi allowlist**: hanya field `text/image/product/product_context/system`; **tak pernah** menyentuh path `internalNotes` maupun stok internal (defense-in-depth — Admin SDK melewati rules, jadi proxy adalah satu-satunya penjaga).
- **Validasi**: `text` ≤ 2.000 char; tipe customer hanya `text|image`; upload ≤ 5 MB, MIME image/jpeg|png|webp **+ `validateImageMagicBytes`** (reuse) untuk blok SVG/polyglot XSS.
- **Rate-limit**: ≤ 20 pesan/menit per member.

### 5.3 Perubahan rules internal `users` (perlu persetujuan — sudah di-acc)
`canHandleCustomer` **wajib** dijaga di **DUA** cabang, sesuai pola anti "hapus-lalu-buat-ulang" yang sudah ada:
- **UPDATE self**: `canHandleCustomer` immutable (== nilai lama) — sederet `role/active/ikutAbsensi`.
- **CREATE self**: `request.resource.data.get('canHandleCustomer', false) == false` — karyawan tak bisa self-grant lewat delete-doc → recreate. Hanya owner boleh set `true`.
- **Uji emulator**: skenario delete→recreate & update self harus gagal menaikkan hak.

### 5.4 Auth server-to-server (dua endpoint baru, keduanya menghadap publik)
- **Webhook CF→Next.js (push balik)**: wajib **shared-secret/HMAC** (env, dibandingkan constant-time) yang hanya dipegang CF tokochat; validasi bentuk `{chatId,customerId,messageId,lastMessageText,lastMessageType}`; **dedupe by `messageId`** (retry CF tak double-push). Tanpa ini, siapa pun yang tahu URL bisa spam notifikasi "toko" palsu ke device customer.
- **Catalog-search NLCATTER→Next.js (product picker)**: NLCATTER (Firebase Auth project berbeda) **tak** punya sesi member. Autentikasi via **staff Firebase ID token tokochat diverifikasi server-side (Admin SDK)** + syarat pemanggil `owner || canHandleCustomer`; **atau** shared-secret di env. Endpoint **hanya** mengembalikan field customer-facing (nama/slug/harga/stok/gambar) — **tak pernah** `hargaModal`/field internal.

### 5.5 Jaminan isolasi
Tak ada principal customer di tokochat → semua rule internal berbasis `isSignedIn()` **tetap valid & tak disentuh** selain §5.3. `notifyNewMessage` tetap terikat `chats/**` saja; `notifyNewCustomerMessage` menghitung penerima **server-side dari koleksi users** (bukan array yang bisa dipengaruhi customer). Payroll/attendance/internalChats/stockAdjustment tak pernah terekspos ke Natalo.

---

## 6. Realtime & Notifikasi (FCM)

| Event | Penerima | Jalur |
|---|---|---|
| Customer kirim pesan (termasuk pesan pertama = buat room) | Staff (owner + `canHandleCustomer`) | CF `notifyNewCustomerMessage` → FCM token staff (tokochat). **Debounce/coalesce** burst agar tak N push. |
| Staff balas | Customer | CF → webhook (shared-secret) → Next.js → FCM customer (kredensial natalopetshop) |

- **Payload tanpa PII**: `title` generik ("Natalo Petshop"), `body` boleh cuplikan pesan (keputusan sadar; **tak** memuat nama/telp/order), `data:{ type:'customer_chat', chatId }`.
- **Kegagalan (ditangani, bukan diabaikan)**: webhook down/5xx → CF retry (Cloud Tasks / retry-on-non-2xx) atau idempoten by `messageId`; token FCM basi (`NotRegistered`/`InvalidRegistration`) → invalidasi token tersimpan; app customer melakukan **catch-up fetch penuh saat buka chat** (bukan cuma poll 3 dtk) supaya balasan yang push-nya jatuh tetap tersusul. Registrasi/refresh token customer di project natalopetshop didaftarkan seperti FCM existing.

---

## 7. UI — Sisi Customer (Natalo App) · gaya e-commerce, biru `#1E5FBF`

### Entry point
- **Tombol chat kontekstual di Detail Produk** (ikon bubble, tanpa teks "NLCATTER"). Membuka room + kirim `product_context` (dengan de-dup, §9). WA lama boleh pindah ke ⋮ atau tetap sekunder.
- **`AppChatButton`** (widget reusable) di header: **Beranda, Keranjang, Transaksi, Pesanan Saya, Detail Pesanan** (Akun di-skip — profil sosial). Catatan integrasi (lihat §16): Beranda & Transaksi sudah memakai header ber-`AppCartButton`/`AppNotificationButton`; **Keranjang, Pesanan Saya, Detail Pesanan belum** — di sana `AppChatButton` = **action AppBar baru** (Keranjang kini hanya punya ikon Wishlist; Pesanan Saya pakai IconButton mentah; Detail Pesanan AppBar-nya title saja).
- Ikon header: **glyph 24px, tap-target 36px** (`VisualDensity.compact` + `constraints 36`), **badge merah `#EF4444`** (chat = dot, cart/bell = angka). Beranda dipadatkan agar 3 ikon muat.

### Layar
- **Gate login** sebelum chat → login/registrasi Natalo existing. `customerId = memberStore.profile.id`.
- **Daftar chat**: layar **sekunder** (back, tanpa bottom nav). Umumnya 1 room. Item + empty state.
- **Room**: header (toko + online), **product-context otomatis**, bubble customer (biru) & admin (putih), **product card** + "Lihat Produk", bubble foto (galeri/kamera), state kirim (`queued/sending/sent/failed` + retry).
- **Kamera & galeri** via `image_picker` (`ImageSource.camera`/`.gallery`); pastikan **`NSCameraUsageDescription` (iOS)** & izin **CAMERA (Android)** ada; bila izin ditolak → tampilkan pesan & fallback ke galeri (masuk §10).
- **Product card → deep link `/products/{slug}`** (rute yang ada; alternatif `/product/{productId}`). Harga/stok final tetap divalidasi saat keranjang/checkout.

### Realtime & persistensi (MVP)
Riwayat **server-authoritative**, di-refetch via REST saat buka (catch-up). Cache lokal = **outbox pesan pending + daftar pesan terakhir** di store berbasis `shared_preferences` JSON, **di-key per `memberId` dan dibersihkan saat logout** (cegah kebocoran antar-member di device sama). **Riwayat offline penuh = non-goal MVP** (bila diperlukan → SQLite, tambah ke §16). Outbox dibatasi (maks antre, kebijakan retry, bertahan restart, urutan by `clientMsgId`+`createdAt`).

---

## 8. UI — Sisi Staff (NLCATTER) · sky blue `#0284C7`

Prinsip: **reuse `chat_screen.dart`** dalam mode `isCustomer`. Bukan layar chat baru.

### Reuse apa adanya
- **AppBar biru** (`_headerAvatar` 36 + nama + presence `white70` + search).
- **Composer `_inputBar()`**: `+` `add_circle_outline` (abu) → emoji/stiker → pill filled `#E9F2F9` "Ketik pesan..." → morph **kamera↔kirim**.
- **Bubble** WA (customer putih kiri, staff `#DCF1FD` kanan, centang biru `#34B7F1`, `ChatPatternBackground`).
- **Attach panel `_attachPanel()`** (tile lingkaran tint 52 + glyph berwarna + label 11).

### Tambahan customer-specific
- **Filter daftar chat**: chip **Semua · Customer · Internal · Grup** ("Sistem" dibuang). Tab Customer = query `customerChats` (§5.1). Item bertanda **"Natalo App"** + badge unread **per-`unreadCount.{myUid}`**.
- **Strip info**: chip status, telp, total belanja, "Lihat Detail".
- **Kartu product-context** & **product card** render.
- **Attach tiles** → **Kamera · Foto · Produk**; PING disembunyikan.
- **⋮ overflow** (elemen baru): **Ubah status** (Open/Menunggu customer/Menunggu staff/Selesai) · **Tambah catatan internal** · **Media** · **Bisukan notifikasi**. (Tanpa Assign.)
- **Catatan internal inline**: kartu kuning "INTERNAL — HANYA STAFF" + penulis; tak pernah ke customer.
- **Sheet detail customer**: nama, telp, total belanja, jumlah order, order terakhir + "terakhir diperbarui" (`summaryUpdatedAt`).
- **Penolakan akses UI**: karyawan tanpa `canHandleCustomer` yang entah bagaimana membuka room → layar "tak berhak" (bukan hanya permission-denied rules).

### Product picker (layar BARU)
Query katalog Natalo via `api/catalog/search` (auth §5.4). Cari nama/SKU, tampil gambar+harga+stok, pilih satu, "Kirim produk". Terkirim → product card → customer tap → `/products/{slug}`.

### Status
`open|waiting_customer|waiting_staff|resolved` (palet StatusInfo asli). Ubah status → baris `system` + memengaruhi filter; audit `statusChangedBy/At`.

---

## 9. Aturan Bisnis

### Produk habis tak bisa di-share (dua lapis)
1. **Picker UI**: stok 0 → redup, ⃠, tak bisa dipilih, keterangan "Stok kosong — tak bisa dikirim ke customer". Pencarian tetap menampilkannya.
2. **Server**: endpoint kirim-product-card **menolak** `stock <= 0` (cek ulang saat kirim; stok bersumber **hanya** dari serializer katalog customer-facing).
3. Kartu yang **sudah terlanjur** terkirim tetap ada di riwayat; customer tap → halaman produk Natalo tampil habis + "Beri tahu saya" (existing).

### De-dup product-context
Proxy hanya menulis `product_context` baru bila `productId != lastContextProductId` (dan bukan pesan terbaru), lalu update `lastContextProductId` → cegah banjir kartu identik saat membuka produk sama berulang.

---

## 10. Error Handling

- Customer belum login → gate login.
- **Izin kamera/galeri ditolak** → pesan + fallback galeri.
- Produk dihapus/nonaktif → card tetap, "Lihat Produk" unavailable.
- Room tak ditemukan / **double-tap / dua device** → proxy create/restore via transaksi (idempoten).
- Upload foto gagal → state `failed` + retry.
- Internet putus → `queued/sending`; **outbox dibatasi** (maks, retry, bertahan restart, urutan).
- Staff tak berhak → room diblokir rules **dan** layar "tak berhak" di UI.
- Customer coba buka chatId lain → ditolak proxy.
- Stok habis saat kirim card → ditolak server.
- **Push balik gagal** (webhook down / token basi) → CF retry + invalidasi token; **catch-up fetch penuh saat buka chat** menyusul balasan yang push-nya jatuh (sisa risiko hanya saat app tertutup).

---

## 11. Analytics / Audit

**Event:** `chat_opened_from_product`, `customer_chat_created`, `customer_message_sent`, `staff_message_sent`, `product_card_sent`, `product_card_opened`, `internal_note_created`, `chat_status_changed`, `chat_resolved`.
**Audit field:** `createdBy/At`, `updatedBy/At`, `statusChangedBy/At`.

---

## 12. Performa & Index

- Pagination: room 30–50 pesan terbaru + `startAfterDocument`. Listener hanya saat screen relevan terlihat.
- **Composite index** (tokochat `firestore.indexes.json`): `customerChats(status ASC, lastMessageAt DESC)`.
- Badge unread staff dari `unreadCount.{myUid}` per room saat list ter-stream (≤ ~30 room) — **per-staff**, bukan skalar (cegah badge hilang untuk semua saat satu staff membuka).

---

## 13. Lingkup MVP & Non-Goals

**MVP (in):** chat teks + foto dua arah, product-context otomatis, daftar chat + riwayat (server-authoritative), staff kirim product card, catatan internal, detail customer, status chat, push dua arah, rules ketat + pagination + isolasi, uji rules & eskalasi.

**Non-goals / ditunda:** voice/video, group/customer-to-customer chat, sinkron WhatsApp, bot AI, routing per topik, **assignment (dihapus)**, quick reply, kartu voucher/order/resi, multi-select kirim produk, reporting dashboard, refresh snapshot manual, **riwayat offline penuh (SQLite)**.

---

## 14. Urutan Implementasi (slices)

1. **Fondasi data & security** — koleksi `customerChats`, rules tokochat (+`customerChats`, +guard `canHandleCustomer` di CREATE & UPDATE), `storage.rules` (`customer_chat_images/`), composite index, service account tokochat untuk Next.js, uji emulator (akses + eskalasi delete→recreate).
2. **Proxy Next.js** — endpoint chat (get/create room transaksional, send text, upload image bytes → UploadThing, fetch dgn projeksi allowlist, snapshot), `api/catalog/search` (auth §5.4), webhook receiver (shared-secret), validasi + magic-byte + rate-limit.
3. **Cloud Functions tokochat** — `notifyNewCustomerMessage` (recipients server-side, `unreadCount.{uid}` increment, debounce) + push-balik webhook (retry/idempoten by `messageId`) → FCM customer.
4. **Natalo customer chat** — `AppChatButton` + entry (2 header punya slot, 3 perlu action baru), gate login, daftar chat, room + product-context de-dup, kamera/galeri + izin, deep link `/products/{slug}`, FCM `customer_chat` + catch-up, cache outbox per-member.
5. **NLCATTER customer inbox** — filter Customer + query, mode `isCustomer` (strip info, attach tiles, ⋮, sembunyikan PING, badge per-uid), catatan internal, product picker + aturan stok, sheet detail (+`summaryUpdatedAt`), status, penolakan akses UI.
6. **Uji & pengerasan** — rules/eskalasi test, isolasi, push dua arah + kegagalan, regresi chat internal (`notifyNewMessage` tetap `chats/**`).

---

## 15. Acceptance Criteria

- [ ] Customer menekan ikon chat dari detail produk & langsung masuk room (tanpa pilih topik).
- [ ] Product context muncul (tanpa duplikat saat buka produk sama berulang).
- [ ] Customer kirim teks & foto (galeri **dan** kamera); masuk real-time ke Customer Inbox.
- [ ] Staff membalas; balasan tampil di Natalo (real-time saat terbuka; tersusul via catch-up bila push jatuh).
- [ ] Staff mengirim product card; produk habis **tak bisa** dikirim (UI + server).
- [ ] Customer membuka product card → detail produk (`/products/{slug}`).
- [ ] Staff menulis catatan internal yang **tak pernah** terlihat customer.
- [ ] Staff mengubah status chat; badge unread **per-staff** benar (tak hilang untuk staff lain).
- [ ] Staff membuka detail customer (nama, telp, order, total belanja, kesegaran).
- [ ] Customer tak dapat membaca chat customer lain (ditegakkan proxy).
- [ ] Customer tak dapat membaca chat internal/stok/gaji/absensi/catatan internal.
- [ ] Karyawan tak bisa self-grant `canHandleCustomer` (update **maupun** delete→recreate) — teruji emulator.
- [ ] Endpoint katalog & webhook **terautentikasi** (tak ada endpoint publik telanjang).
- [ ] Upload gambar tervalidasi (MIME + magic-byte).
- [ ] NLCATTER tidak memuat seluruh message/chat sekaligus (pagination).
- [ ] Tidak ada regresi pada chat internal NLCATTER (`notifyNewMessage` tetap `chats/**`).
- [ ] Security rules diuji (emulator/otomatis).
- [ ] Push notification berfungsi dua arah (payload tanpa PII).

---

## 16. Berkas yang Terpengaruh (tingkat tinggi)

**`natalopetshopflutter/flutter_app/` (Natalo Flutter):** `widgets/app_chat_button.dart` (baru); integrasi header — Beranda (`home_screen.dart`) & Transaksi (`transactions_screen.dart`) sudah punya slot; **Keranjang (`cart_screen.dart`), Pesanan Saya (`member_orders_screen.dart`), Detail Pesanan (`member_order_detail_screen.dart`) perlu action AppBar baru**; `screens/chat_list_screen.dart` + `chat_room_screen.dart` (baru); `models/customer_chat*.dart` (baru); `services/chat_service.dart` (baru, REST); `state/chat_store.dart` (baru, ChangeNotifier, cache per-member); integrasi `product_detail_screen.dart`; handler FCM `customer_chat` + catch-up di `push_notification_service.dart`; route baru di `main.dart`; **iOS `Info.plist` `NSCameraUsageDescription` + Android `CAMERA` permission** bila belum ada.

**`natalopetshopflutter/app/` (Next.js):** `api/chat/*` (proxy: room transaksional, upload image → UploadThing via `lib/uploadthing`, fetch allowlist, snapshot), `api/catalog/search` (auth §5.4), webhook receiver (shared-secret, FCM ke customer), integrasi Admin SDK tokochat (service account, env), reuse validator magic-byte.

**`NLCHAT/` (NLCATTER Flutter):** mode `isCustomer` di `screens/chat_screen.dart` + filter di `chat_list_screen.dart`, `screens/customer_product_picker.dart` (baru), sheet detail customer, render catatan internal, kontrol status, penolakan akses UI, `models/customer_chat*.dart` (baru), `functions/index.js` (`notifyNewCustomerMessage` + webhook push-balik), `firestore.rules` (+`customerChats`, +guard `canHandleCustomer` CREATE & UPDATE), `firestore.indexes.json` (+index), `storage.rules` (+`customer_chat_images/`).

---

## 17. Keputusan Terbuka / Risiko

- **Kredensial lintas-project & secret**: service account tokochat (Next.js), shared-secret webhook, secret/verifier katalog — simpan di env Vercel, rotasi berkala.
- **Konsistensi harga/stok**: picker/card pakai snapshot katalog Natalo; validasi final tetap saat checkout.
- **Kesegaran snapshot profil** = interaksi terakhir customer; `summaryUpdatedAt` menandai; refresh manual = tahap lanjut.
- **Skala push staff**: notifikasi ke semua `canHandleCustomer`; untuk toko kecil aman; bila banyak staff → mute/jam-kerja (tahap lanjut).
- **Storage gambar customer di UploadThing** = URL publik-permanen tak-tertebak (tanpa ACL objek); bila kelak butuh privasi objek → signed/short-lived URL (tahap lanjut).
