# Design Spec — Integrasi Chat Customer Natalo ↔ NLCATTER

- **Tanggal:** 2026-07-06
- **Status:** Draft desain (belum ada implementasi) · **Rev 5** (BATALKAN role `admin` → kembali ke flag `canHandleCustomer`; + temuan review kelengkapan: identitas `User.id`, deep-link notif, badge unread, resolved/reopen, sumber kill-switch, copy status, kontrak endpoint, store rate-limit/idempotency, ChatThread mati)
- **Repo terpengaruh:** `natalopetshopflutter/` (app customer Flutter + web/backend Next.js) dan `NLCHAT/` (app internal NLCATTER Flutter)

> **Catatan revisi Rev 5 (penting):** Rev 4 sempat mengganti flag `canHandleCustomer` jadi nilai `role:'admin'` sungguhan. Itu **dibatalkan** karena review menemukan `role == 'karyawan'` dipakai sebagai **filter** di banyak tempat produksi (absensi, jadwal libur, penggajian — Dart + 3 lokasi `functions/index.js`); menaikkan karyawan→`admin` akan diam-diam mengeluarkannya dari absensi/payroll/ping-stok. Kembali ke **flag boolean `canHandleCustomer`** yang orthogonal terhadap tier kepegawaian.

---

## 0. Ringkasan

Customer di **Natalo App** menekan ikon chat (ala e-commerce umum) dan mengobrol langsung dengan toko. Pesan **tidak** ke WhatsApp — masuk real-time ke **Customer Inbox di NLCATTER** (app internal staff), staff membalas, balasan tampil di Natalo App. Tanpa langkah "pilih topik". Bila dibuka dari halaman produk/pesanan, konteks terbawa otomatis.

**MVP mencakup:** chat teks + foto dua arah, product-context & order-context otomatis, jam operasional + auto-reply di luar jam, auto-greeting pesan pertama, typing indicator + banner "sedang dibalas", staff kirim product card, catatan internal, detail customer, status chat (+resolved/reopen), badge unread customer, push dua arah (dengan deep-link ke room), pemisahan & keamanan data internal, kill-switch/feature-flag.

---

## 1. Temuan Audit (Phase 0) — yang mengubah premis brief

| Aspek | Natalo (customer) | NLCATTER (staff) |
|---|---|---|
| Project Firebase | `natalopetshop-818c4` | `tokochat-a8879` (**berbeda**) |
| Auth | Token API sendiri (email/pw + WA OTP) via Next.js — **bukan Firebase Auth**; `getSession('CUSTOMER')` → `session.sub` = Prisma `User.id` | Firebase Auth (email/pw) |
| Data utama | Next.js/Prisma/Postgres (REST). Customer = Prisma **`model User`** (id = cuid) | Firestore |
| Pakai Firestore? | **Tidak** (Firebase hanya FCM/analytics/crashlytics) | Ya, intensif |
| Upload foto | **UploadThing** (via `lib/uploadthing` `uploadToUT` + `validateImageMagicBytes`); Bunny CDN hanya untuk video Feed | Firebase Storage tokochat (`chat_images/{chatId}/`) |
| FCM token customer | `PushSubscription` (Prisma), `userId` = `User.id`, endpoint prefix `fcm:` | `users/{uid}.fcmTokens` (Firestore) |
| Cloud Functions | Tidak (backend Next.js) | 23 fungsi (Node 22): `notifyNewMessage`, `sendChatReply`, dll |
| State mgmt | ChangeNotifier singleton manual | Provider + StreamBuilder |
| Role | member (customer) | **hanya** `owner` / `karyawan` (tak ada admin/CS) |

**Chat customer lama (Prisma, MATI):** schema Prisma sudah punya `ChatThread` (`@@unique([userId])`, status OPEN) + `ChatMessage` (senderRole ADMIN/CUSTOMER, content, readAt). **Tak ada fitur yang memakainya** — hanya dirujuk di `api/account/delete` (cascade) & `api/admin/reset-all`. Ini **stub mati** sisa percobaan lama. Firestore `customerChats` tetap **sumber tunggal** (Topologi A). Tabel ini diabaikan; opsi bersihkan dari schema = tahap lanjut (di luar MVP).

**Konsekuensi kunci:** dua project Firebase terpisah, app customer murni REST/Prisma. Semua data customer/order/produk di sisi Next.js; NLCATTER pulau Firebase terpisah. Butuh "jembatan" — Topologi A.

---

## 2. Arsitektur — Topologi A (Proxy via Next.js)

**Sumber kebenaran:** koleksi `customerChats` di **Firestore tokochat**. App customer tetap REST; **backend Next.js jadi proxy** (service-account tokochat / Admin SDK) yang menulis ke tokochat *atas nama* customer. NLCATTER membaca/menulis native. Customer **tak pernah** punya identitas Firebase di tokochat.

```
Natalo App (REST, tanpa Firestore)
   │  POST /api/chat/* (sesi member Natalo → User.id, + clientMsgId)
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
1. Customer → `POST /api/chat/send` (sesi member Natalo → `userId = session.sub`; body memuat **`clientMsgId` (UUID)** untuk idempotensi).
2. Next.js **transaksi** create-if-absent room `cust_<userId>`; append message idempoten (no-op bila `clientMsgId` sudah ada); segarkan snapshot profil (merge). Bila room baru & dalam jam operasional → tulis auto-greeting; bila luar jam → auto-reply away (§4.6).
3. CF tokochat `notifyNewCustomerMessage` → hitung penerima **server-side** (owner + `canHandleCustomer`), naikkan `unreadCount.{uid}` per penerima, kirim FCM ke token staff (di tokochat). NLCATTER menerima update **live**.
4. Staff balas di NLCATTER (native) → tulis ke Firestore tokochat; naikkan `unreadForCustomer`.
5. CF tokochat → **webhook (ber-shared-secret)** ke Next.js → Next.js resolve `customerId (=User.id)` → `PushSubscription` (Prisma) → **FCM ke customer** (kredensial natalopetshop), payload memuat `deepLink` ke room. App customer **catch-up fetch** saat dibuka; saat layar chat terbuka juga short-poll ~3 dtk.

**Kenapa A (bukan B/C):** A menaruh kerumitan lintas-project di **server** (aman, service account), kedua app client tetap sesuai bentuknya, dan **rules internal NLCATTER hampir tak disentuh**. B membebani kedua app. C menulis ulang semua rules internal — risiko tinggi, ditolak.

**Realtime:** staff = listener native (<0.5 dtk). Customer = FCM + catch-up/short-poll (~1–3 dtk saat layar terbuka).

---

## 3. Model Peran & Akses

- **Hanya dua role: `owner` dan `karyawan`.** "Admin"/"CS" = sebutan bisnis; teknis = `karyawan`.
- **Akses Customer Inbox** = `isOwner() || users.canHandleCustomer == true`. `canHandleCustomer` = **field boolean** di `users/{uid}`, di-set **hanya owner** lewat toggle di kelola-user (§8). Karyawan tanpa flag tak pernah dapat akses.
- **Kenapa flag, BUKAN role tier (koreksi Rev 5 — pelajaran dari review):** field `role` dipakai sebagai **filter kesetaraan** `role == 'karyawan'` di banyak alur produksi — `attendance_screen.dart:93`, `set_libur_sheet.dart:193`, `payroll_list_screen.dart:59`, dan **`functions/index.js` (3×)**. Menambah nilai role baru (mis. `admin`) akan **diam-diam mengeluarkan** staff tsb dari absensi, jadwal libur, penggajian, & ping stok. Flag boolean **orthogonal** terhadap tier kepegawaian → nol risiko ke fitur lain.
- **`canHandleCustomer` wajib immutable-by-self** (guard di CREATE **dan** UPDATE rule `users`, §5.3) supaya karyawan tak bisa self-grant lewat REST/APK. (Ini SATU-satunya sentuhan ke rules internal.)
- **Tanpa assignment.** Customer Inbox = **antrean bersama**; siapa pun yang berwenang (owner + staff ber-flag) menangani chat mana saja.
- **Penanda "sedang dibalas"** (cegah tabrakan jawaban saat >1 staff eligible membuka room sama): reuse field `typingStaff:{uid,name,at}` (§4). Ke **customer** → generik "sedang mengetik…" (§7). Ke **staff lain** yang membuka room sama → banner **"Sedang dibalas oleh {name}"** (§8). Satu field, dua tampilan — tanpa assignment formal.
- Semua staff penangan kapabilitas sama (balas, ubah status, catatan internal).
- Ke customer, identitas pengirim selalu **"toko"** ("Natalo Petshop & Aquarium"), tak pernah nama/role staff.

---

## 4. Model Data (Firestore tokochat)

Koleksi **baru & terpisah** `customerChats` (bukan flag di `chats` internal). Tab "Customer" query `customerChats`; tab "Internal/Grup" tetap `chats`.

### 4.1 Skema

**`customerChats/{chatId}`** — `chatId = cust_<userId>` di mana **`userId` = Natalo Prisma `User.id` (cuid)** (deterministik, 1 room/customer, idempoten):
```
customerId            // = Natalo User.id (cuid), BUKAN uid Firebase, BUKAN 'member_profile.id'
customerName, customerPhone            // snapshot dari Prisma User
summary: { totalBelanja, orderCount, lastOrder:{inv,status,total} }  // snapshot
summaryUpdatedAt      // kapan snapshot diambil
status                // open | waiting_customer | waiting_staff | resolved
statusChangedBy, statusChangedAt       // audit
lastMessageText, lastMessageType, lastMessageAt, lastMessageSender   // customer|staff
unreadCount: { <staffUid>: int }       // per-staff (pola chat internal)
unreadForCustomer: int                 // skalar (1 principal customer)
lastContextProductId?, lastContextOrderId?   // de-dup context
greetingSentAt?       // sekali per room — cegah auto-greeting berulang
typingStaff?: { uid, name, at }        // typing→customer + "sedang dibalas"→staff (kadaluarsa >10dtk)
source                // 'natalo_app'
createdAt, updatedAt
```

**`.../messages/{msgId}`**:
```
clientMsgId           // UUID dari client → idempotensi & rekonsiliasi optimistic
senderRole            // customer | staff
senderId              // User.id (customer) | uid Firebase (staff)
senderName
type                  // text | image | product | product_context | order_context | system
text
image?: { url }       // URL UploadThing (§4.3)
product?: { productId, slug, name, imageUrl, price, stock }
order?: { orderNumber, status, total }   // untuk order_context
auto?: bool           // true = pesan sistem otomatis (greeting/away)
staffOnly?: bool      // true = system message internal (transisi status waiting_*) → TAK ikut ke customer (§5.2)
createdAt             // server timestamp — kunci urutan
status                // queued | sending | sent | failed  (optimistic UI)
readByStaffAt?, readByCustomerAt?
```
Tipe yang **boleh dibuat customer**: hanya `text` & `image`. Sisanya staff/proxy.
- `system auto:true` = **auto-greeting** & **auto-reply away** → bubble berlabel "Balasan otomatis" (§7).
- `system` transisi status: `waiting_customer`/`waiting_staff` ditulis `staffOnly:true` (tak ke customer); **`resolved`/`reopened`** ditulis TANPA `staffOnly` dengan copy ramah-customer (§8) — customer tak pernah melihat jargon status mentah.

**`.../internalNotes/{noteId}`** — subkoleksi terpisah, tak pernah ke customer: `authorId, authorName, text, createdAt` (immutable).

### 4.2 Kepemilikan tulis, urutan & idempotensi
- **Proxy (customer) menulis HANYA**: `customerName/customerPhone/summary/summaryUpdatedAt/lastContext*` (merge), append `messages` customer + auto-message, `lastMessage*` sisi customer, reset `unreadForCustomer` (saat customer fetch), auto-reopen `status` (§8). Increment via `FieldValue.increment`.
- **NLCATTER (staff) menulis HANYA**: `status/statusChanged*`, append `messages` staff, `lastMessage*` sisi staff, reset `unreadCount.{uid}` (saat buka room), `typingStaff`.
- **CF menulis**: `unreadCount.{uid}` increment per penerima; `unreadForCustomer` increment (saat balasan staff).
- **Room create/restore**: proxy pakai **transaksi** / `set(merge:true)` dgn `createdAt` hanya-jika-absent → cegah double-init (double-tap / dua device).
- **Urutan**: `createdAt` server; klien rekonsiliasi optimistic via `clientMsgId`.

### 4.3 Storage gambar — kedua arah lewat UploadThing
Semua foto **chat customer** (customer & staff) via proxy Next.js → **UploadThing**. Fitur NLCATTER lain tetap Firebase Storage (tak disentuh).
- **Customer → proxy → UploadThing**: `api/chat/send-image`, reuse `uploadToUT` + `validateImageMagicBytes` (pola `api/reviews/upload`).
- **Staff → NLCATTER → proxy → UploadThing**: NLCATTER unggah bytes ke `api/chat/staff-send-image` (auth token staff §5.4), proxy validasi + `uploadToUT`, kembalikan URL; NLCATTER tulis pesan `image` (native).
- Keduanya hanya URL di dokumen pesan. `storage.rules` tokochat **tak berubah**. Kontrol akses = key tak-tertebak UploadThing (signed-URL = tahap lanjut).

### 4.4 Snapshot profil
Nama/telepon/`summary` = snapshot Prisma, ditulis proxy tiap customer berinteraksi; `summaryUpdatedAt` menandai kesegaran. NLCATTER tak pernah menyentuh DB Natalo.

### 4.5 Jam operasional (`app_settings/chatHours` di tokochat)
Reuse koleksi `app_settings` NLCATTER (baca semua user login, tulis owner):
```
app_settings/chatHours: {
  timezone: 'Asia/Jakarta',
  days: { mon:{open:'08:00',close:'21:00'}, ..., sun:{open:null,close:null} },  // null = tutup
  awayMessage: 'Terima kasih sudah menghubungi Natalo 🐾 Saat ini di luar jam operasional ({jamBuka}–{jamTutup} WIB). Pesanmu sudah masuk, akan kami balas saat toko buka.'
}
```
Status "online"/"di luar jam" dihitung dari config ini (bukan presence staff). **Evaluasi jam di server harus konversi ke WIB eksplisit** (Vercel jalan UTC) — pakai helper TZ (mis. `Intl`/`date-fns-tz`) dengan offset config, bukan `new Date()` polos. Template `{jamBuka}/{jamTutup}` disubstitusi proxy dari config hari tsb.

### 4.6 De-dup context & auto-message
- **`product_context`/`order_context`**: proxy tulis baru hanya bila `id != lastContext{Product,Order}Id` (dan bukan pesan terbaru), lalu update field-nya.
- **Auto-greeting**: sekali saat room baru (`greetingSentAt` kosong) & dalam jam operasional.
- **Auto-reply away**: pesan customer pertama dalam sesi di luar jam (bukan tiap pesan). Greeting & away **saling eksklusif** di pembuka.

---

## 5. Keamanan — dua lapis + auth server-to-server

### 5.1 Firestore rules (tokochat): staff-only
```
match /customerChats/{chatId} {
  function canCS() { return isSignedIn() && (isOwner()
    || get(/databases/$(database)/documents/users/$(request.auth.uid))
         .data.get('canHandleCustomer', false) == true); }
  allow read, list, create, update: if canCS();
  allow delete: if false;
  match /messages/{m}      { allow read, create, update: if canCS(); allow delete: if false; }
  match /internalNotes/{n} { allow read, create: if canCS(); allow update, delete: if false; }
}
```
Query tab Customer: `where status in [open,waiting_customer,waiting_staff] orderBy lastMessageAt desc limit N` (index §12). Karyawan tanpa flag → `list` ditolak (diuji emulator).

### 5.2 Proxy Next.js: authz sisi customer
- **Sesi member Natalo** diverifikasi via `getSession('CUSTOMER')` → **`userId = session.sub` (= Prisma `User.id`)**.
- Paksa `chatId == cust_<userId>` (tak bisa akses chat lain).
- **Fetch pakai projeksi allowlist**: hanya `text/image/product/product_context/order_context/system(non-staffOnly)`; **tak pernah** `internalNotes`, pesan `staffOnly`, atau stok internal. **`unreadForCustomer`** disertakan di respons **room-summary** (bukan di stream pesan) untuk badge (§7).
- **Validasi**: `text` ≤ 2.000 char; tipe customer `text|image`; upload ≤ 5 MB, MIME jpeg|png|webp + `validateImageMagicBytes`.
- **Rate-limit** ≤ 20 pesan/menit per member — **store: Upstash Redis** (Vercel stateless) atau tabel Prisma berjendela; fail-open bila store tak terjangkau (jangan blokir chat karena outage rate-limiter).

### 5.3 Rules internal `users` — SATU perubahan: `canHandleCustomer` immutable-by-self
`canHandleCustomer` **wajib** dijaga di DUA cabang rule `users` (pola sama `role`/`active`/`ikutAbsensi`):
- **UPDATE self**: `request.resource.data.get('canHandleCustomer',false) == resource.data.get('canHandleCustomer',false)` (immutable).
- **CREATE self**: `request.resource.data.get('canHandleCustomer',false) == false` (cegah self-grant lewat delete→recreate).
- Hanya **owner** yang boleh set `true`. Diuji emulator (update self & delete→recreate ke `true` harus DITOLAK).

### 5.4 Auth server-to-server (endpoint baru menghadap publik)
Kontrak & auth harus eksplisit:
- **Webhook CF→Next.js (push balik)** `POST /api/chat/webhook`: **shared-secret/HMAC** header (env, constant-time), body `{chatId,customerId,messageId,lastMessageText,lastMessageType}`; **dedupe by `messageId`** — store: tabel Prisma `unique(messageId)` (in-memory tak selamat cold-start). Resolve `customerId → PushSubscription.where({userId:customerId, endpoint startsWith 'fcm:'})` → kirim via `lib/fcm.ts`.
- **Catalog-search** `GET /api/catalog/search` & **Staff-send-image** `POST /api/chat/staff-send-image` (multipart, field `file`): NLCATTER kirim `Authorization: Bearer <tokochat idToken>`; Next.js **verifikasi via Admin SDK `verifyIdToken`** (Admin SDK sudah diinisialisasi terhadap tokochat, §2) → `getFirestore().doc('users/'+uid).get()` → wajib `isOwner || canHandleCustomer`. Response image: `{url}`; error: 400/401/403/415/500. Catalog **hanya** field customer-facing (tak pernah `hargaModal`).

### 5.5 Jaminan isolasi
Tak ada principal customer di tokochat → rule internal berbasis `isSignedIn()` **tetap valid** selain §5.3. `notifyNewMessage` tetap `chats/**`; `notifyNewCustomerMessage` hitung penerima **server-side dari koleksi users** (owner + `canHandleCustomer`). Data internal tak pernah terekspos ke Natalo.

---

## 6. Realtime & Notifikasi (FCM)

| Event | Penerima | Jalur |
|---|---|---|
| Customer kirim pesan (termasuk pesan pertama) | Staff (owner + `canHandleCustomer`) | CF `notifyNewCustomerMessage` → FCM token staff (tokochat). **Debounce/coalesce** burst. |
| Staff balas | Customer | CF → webhook (shared-secret) → Next.js → resolve `User.id`→`PushSubscription`→FCM (kredensial natalopetshop) |

- **Payload tanpa PII, DENGAN deep-link**: `title` generik ("Natalo Petshop"), `body` cuplikan pesan (tanpa nama/telp/order), `data:{ type:'customer_chat', chatId, deepLink:'/chat/'+chatId }`.
- **Tap notifikasi → room (WAJIB):** handler push existing (`_handleMessage`) hanya me-route bila ada `data.deepLink`/`url`; tanpa itu customer terbuang ke Beranda. Karena itu payload **wajib** menyertakan `deepLink`, DAN `deep_link_service.dart` **ditambah case `/chat/{chatId}`** yang membuka room. (Masuk §16 & acceptance.)
- **Kegagalan (ditangani)**: webhook down/5xx → retry (Cloud Tasks/retry-on-non-2xx) + idempoten `messageId`; token basi → invalidasi; app customer **catch-up fetch penuh saat buka chat**. Registrasi/refresh token customer di project natalopetshop (reuse `push_notification_service` + `PushSubscription`).

---

## 7. UI — Sisi Customer (Natalo App) · gaya e-commerce, biru `#1E5FBF`

### Entry point
- **Tombol chat kontekstual di Detail Produk** (ikon bubble). Membuka room + `product_context` (de-dup §9). WA lama boleh pindah ke ⋮.
- **`AppChatButton`** (widget reusable) di header: **Beranda, Keranjang, Transaksi, Pesanan Saya, Detail Pesanan** (Akun di-skip). Beranda & Transaksi sudah punya slot; Keranjang/Pesanan Saya/Detail Pesanan = **action AppBar baru** (§16).
- Ikon header: glyph 24px, tap-target **36px**, badge merah `#EF4444`.
- **Badge unread**: `AppChatButton` menampilkan dot/angka dari **`unreadForCustomer`** (via `GET /api/chat/unread` → `{unread:int}`, atau disertakan di room-summary fetch), refresh saat resume + saat push masuk (pola `notificationRefreshTick` existing). (Field ada di Firestore tapi **harus** diekspos lewat endpoint — tak masuk stream pesan.)
- **Guest** (belum login) menekan ikon chat → gate "Masuk untuk chat dengan Natalo" → login/registrasi existing.

### Layar
- **Daftar chat**: layar sekunder (back, tanpa bottom nav). Umumnya 1 room. `customerId = memberStore.profile.id` (= `User.id`).
- **Room**: header toko status **"Online"** (dot hijau, dalam jam §4.5) / **"Di luar jam operasional"** (ikon jam). **Product-context & order-context** otomatis. Pesan sistem **auto-greeting/away** = bubble kiri berlabel **"Balasan otomatis"**. Saat staff menandai **resolved** → bubble sistem ramah "Percakapan ini ditandai selesai oleh tim Natalo. Kirim pesan lagi kapan saja untuk melanjutkan." — **composer tetap aktif**. Bubble customer (biru)/admin (putih), product card + "Lihat Produk", bubble foto, **typing indicator** ("Natalo sedang mengetik…"), state kirim (`queued/sending/sent/failed` + retry).
- **Re-open**: mengirim pesan ke room `resolved` otomatis membuka kembali (proxy set `status → waiting_staff`) supaya masuk lagi ke antrean staff (§8).
- **Kamera & galeri** via `image_picker`; `NSCameraUsageDescription` (iOS) + `CAMERA` (Android); izin ditolak → pesan + fallback galeri.
- **Product card → deep link `/products/{slug}`**.
- **Order-context**: entry dari Detail Pesanan/Pesanan Saya melampirkan kartu `order_context` (invoice+status+total), de-dup §4.6.

### Realtime & persistensi (MVP)
Riwayat **server-authoritative**, refetch REST saat buka. Cache lokal = outbox pending + pesan terakhir (`shared_preferences` JSON, **di-key per `userId`, dibersihkan saat logout**). Riwayat offline penuh = non-goal.

---

## 8. UI — Sisi Staff (NLCATTER) · sky blue `#0284C7`

Prinsip: **reuse `chat_screen.dart`** dalam mode `isCustomer`. Bukan layar chat baru.

### Reuse apa adanya
- **AppBar biru** (`_headerAvatar` 36 + nama + presence + search).
- **Composer `_inputBar()`**: `+` `add_circle_outline` → emoji → pill `#E9F2F9` "Ketik pesan..." → morph kamera↔kirim.
- **Bubble** WA (customer putih kiri, staff `#DCF1FD` kanan, centang biru `#34B7F1`).
- **Attach panel `_attachPanel()`**.

### Tambahan customer-specific
- **Filter daftar chat**: chip **Semua · Customer · Internal · Grup**. Item tag "Natalo App" + badge unread **per-`unreadCount.{myUid}`**.
- **Strip info**: chip status, telp, total belanja, "Lihat Detail" + **banner "Sedang dibalas oleh {name}"** (untuk staff lain saat `typingStaff` aktif dari staff berbeda).
- **Kartu product/order-context** & **product card** render.
- **Attach tiles** → **Kamera · Foto · Produk**; PING disembunyikan.
- **⋮ overflow**: **Ubah status** (Open/Menunggu customer/Menunggu staff/Selesai) · **Tambah catatan internal** · **Media** · **Bisukan notifikasi**. (Tanpa Assign.)
- **Catatan internal inline**: kartu kuning "INTERNAL — HANYA STAFF".
- **Sheet detail customer**: nama, telp, total belanja, jumlah order, order terakhir + "terakhir diperbarui".
- **Penolakan akses UI**: staff tanpa `canHandleCustomer` (dan bukan owner) yang membuka room → layar "tak berhak".
- **Typing/`typingStaff`**: composer NLCATTER tulis `typingStaff` throttled (~3 dtk), hapus saat berhenti/kirim. Dua konsumen: customer (§7) + banner staff lain.
- **Toggle `canHandleCustomer`** (MODIFY, owner-only): di kelola-user existing (`manage_users_screen.dart`), tambah switch **"Bisa tangani chat customer"** per karyawan di sheet edit-user. Satu-satunya cara menyalakan flag (selain manual Firestore).
- **Editor jam operasional** (layar BARU, owner-only): form per-hari + `awayMessage`, tulis `app_settings/chatHours`.

### Product picker (layar BARU)
Query katalog Natalo via `api/catalog/search` (auth §5.4). Cari nama/SKU, gambar+harga+stok, pilih satu, "Kirim produk". **State wajib**: loading, **no-result** ("Produk tidak ditemukan"), **error/timeout + retry** (panggilan lintas-project). Terkirim → product card → customer tap → `/products/{slug}`.

### Status (open/waiting_customer/waiting_staff/resolved)
Ubah status → update root `status` + audit `statusChangedBy/At` + memengaruhi filter. **Pesan sistem:** transisi `waiting_*` = tak ada bubble ke customer (hanya field status; opsional `system staffOnly:true` untuk jejak staff). **`resolved`** = bubble sistem ramah-customer (§7). **Re-open** (pesan customer masuk ke room resolved) = proxy set `waiting_staff` + bubble "Percakapan dibuka kembali".

---

## 9. Aturan Bisnis

### Produk habis tak bisa di-share (dua lapis)
1. **Picker UI**: stok 0 → redup, ⃠, tak bisa dipilih, keterangan.
2. **Server**: endpoint kirim-card **menolak** `stock <= 0` (cek ulang; stok dari serializer katalog customer-facing).
3. Kartu terlanjur terkirim tetap ada; customer tap → halaman produk tampil habis + "Beri tahu saya".

### De-dup product/order-context
Proxy tulis context baru hanya bila `id != lastContext*Id` — cegah banjir kartu identik.

---

## 10. Error Handling

- Customer belum login → gate login (guest: "Masuk untuk chat dengan Natalo").
- Izin kamera/galeri ditolak → pesan + fallback galeri.
- Produk dihapus/nonaktif → card tetap, "Lihat Produk" unavailable.
- Room tak ditemukan / double-tap / dua device → proxy create/restore via transaksi.
- Upload gagal → `failed` + retry. Internet putus → `queued/sending`; outbox dibatasi.
- Staff tak berhak → diblokir rules + layar "tak berhak".
- Customer buka chatId lain → ditolak proxy. Stok habis saat kirim → ditolak server.
- **Tap notifikasi** → membuka room (butuh `deepLink` + case `/chat`, §6) — bukan Beranda.
- **Pesan ke room resolved** → auto-reopen (§8), tak hilang senyap.
- **Push balik gagal** → CF retry + invalidasi token; catch-up fetch saat buka.
- **Product picker** search gagal/timeout/kosong → state jelas + retry (§8).

---

## 11. Analytics / Audit

**Event:** `chat_opened_from_product`, `chat_opened_from_order`, `customer_chat_created`, `customer_message_sent`, `staff_message_sent`, `product_card_sent`, `product_card_opened`, `internal_note_created`, `chat_status_changed`, `chat_resolved`, `chat_reopened`, `auto_greeting_sent`, `auto_away_reply_sent`.
**Audit field:** `createdBy/At`, `updatedBy/At`, `statusChangedBy/At`.
**Sink:** sisi customer → **Firebase Analytics** (reuse `firebase_analytics` di `flutter_app`); sisi staff/proxy → **log terstruktur** ke Cloud Functions/Vercel log (tanpa koleksi baru). Dashboard = tahap lanjut.

---

## 11b. Kill-Switch & Rollout

Wajib bisa **dimatikan cepat tanpa rilis ulang** (menyentuh rules produksi + endpoint publik baru). **Sumber flag (didefinisikan konkret — tak ada mekanisme existing):**
- **Store**: baris `AppConfig` di Prisma (mis. `{ key:'chatEnabled', value:'true' }`) — sumber tunggal. Owner/dev mengubahnya (admin toggle atau flip baris manual untuk MVP).
- **Customer app**: `GET /api/chat/config` → `{chatEnabled:bool}`, di-fetch saat app start + di-cache. `false` → sembunyikan `AppChatButton` & tombol chat detail produk; room existing bisa dibaca tapi composer nonaktif ("Chat sedang dalam pemeliharaan").
- **Proxy**: semua handler `api/chat/*` cek `AppConfig.chatEnabled` di awal; mati → `503` generik.
- **NLCATTER**: baca **mirror** `app_settings/chatConfig` di tokochat (ditulis proxy saat flag berubah, karena NLCATTER tak bisa baca Postgres) → banner "Fitur chat customer nonaktif sementara".
- **Default fail-open**: bila store/endpoint tak terjangkau → anggap enabled (outage config jangan mematikan chat; kill-switch = tindakan off eksplisit).

---

## 11c. Logging Kegagalan Lem Lintas-Sistem

Kegagalan titik sambung harus **terlihat** (observability §10):
- Webhook push-balik gagal (retry habis) → log `{event:'webhook_delivery_failed', chatId, messageId, attempt}` (Cloud Logging tokochat).
- Proxy gagal tulis tokochat → log Vercel + response error ke client (bukan silent-success).
- FCM token invalid → log `{event:'fcm_token_invalidated', userId}` sebelum hapus token.
- Bukan dashboard/alerting (di luar MVP) — cukup tercatat untuk debug manual.

---

## 12. Performa & Index

- Pagination: room 30–50 pesan + `startAfterDocument`. Listener hanya saat screen terlihat.
- **Composite index** (tokochat): `customerChats(status ASC, lastMessageAt DESC)`.
- Badge unread staff dari `unreadCount.{myUid}` per room (per-staff, bukan skalar).

---

## 13. Lingkup MVP & Non-Goals

**MVP (in):** chat teks+foto dua arah, product/order-context, jam operasional + auto-reply, auto-greeting, typing + banner "sedang dibalas", badge unread customer, daftar chat + riwayat, staff kirim product card, catatan internal, detail customer, status +resolved/reopen, **toggle `canHandleCustomer` (owner)**, editor jam operasional (owner), push dua arah + deep-link, rules ketat (+guard `canHandleCustomer`) + pagination + isolasi, kill-switch.

**Non-goals / ditunda:** voice/video, group/customer-to-customer, sinkron WA, bot AI, routing per topik, assignment, quick reply, kartu voucher/resi, multi-select produk, reporting/alerting dashboard, refresh snapshot manual, riwayat offline penuh (SQLite), block/report customer, retensi/hapus data, **pembersihan tabel Prisma `ChatThread`/`ChatMessage` mati**.

---

## 14. Urutan Implementasi (slices)

1. **Fondasi data & security** — koleksi `customerChats`, rules tokochat (+`customerChats` canCS berbasis `owner||canHandleCustomer`; **+guard `canHandleCustomer` immutable di CREATE & UPDATE `users`**, §5.3), composite index, service account tokochat, uji emulator (akses + anti-eskalasi flag). (`storage.rules` tak berubah, §4.3.)
2. **Proxy Next.js** — `api/chat/*` (room transaksional, send text, send-image→UploadThing, fetch allowlist, room-summary+unread, snapshot, auto-greeting/away, resolve jam WIB), `api/chat/config` (kill-switch) + mirror `app_settings/chatConfig`, `api/catalog/search` + `api/chat/staff-send-image` (auth §5.4), `api/chat/webhook` (shared-secret + dedupe messageId), rate-limit store.
3. **Cloud Functions tokochat** — `notifyNewCustomerMessage` (recipients owner+`canHandleCustomer`, `unreadCount.{uid}` increment, debounce) + push-balik webhook (retry/idempoten, payload deepLink) → FCM customer.
4. **Natalo customer chat** — `AppChatButton` + entry (+order-context) + **badge unread** dari `/api/chat/unread`, gate login (+guest copy), daftar chat, room + context de-dup + status online/away + auto-message berlabel + resolved/reopen, typing indicator, kamera/galeri + izin, **deep-link `/chat/{chatId}` di `deep_link_service` + payload handler**, FCM `customer_chat` + catch-up, cache outbox per-`userId`, cek `chatFeatureEnabled`.
5. **NLCATTER customer inbox** — filter Customer, mode `isCustomer` (strip info + banner "sedang dibalas", attach tiles, ⋮, badge per-uid, tulis `typingStaff`), catatan internal, product picker + aturan stok + empty/error state, sheet detail, status +resolved/reopen copy, penolakan akses UI, **toggle `canHandleCustomer`** di `manage_users_screen.dart` (modify), **editor jam operasional** (baru), banner kill-switch (baca mirror).
6. **Uji & pengerasan** — rules + anti-eskalasi flag test, isolasi, push dua arah + deep-link + kegagalan (+logging §11c), regresi chat internal, uji kill-switch end-to-end.

---

## 15. Acceptance Criteria

- [ ] Customer menekan ikon chat dari detail produk & langsung masuk room (tanpa pilih topik).
- [ ] Product/order context muncul (tanpa duplikat saat buka ulang untuk item sama).
- [ ] Customer kirim teks & foto (galeri **dan** kamera); masuk real-time ke Customer Inbox.
- [ ] Staff membalas; balasan tampil di Natalo (real-time saat terbuka; tersusul via catch-up).
- [ ] **Tap notifikasi balasan → langsung ke room chat, bukan Beranda.**
- [ ] **Ikon chat customer menampilkan badge unread saat ada balasan belum dibaca** (dari `unreadForCustomer`).
- [ ] Staff mengirim product card; produk habis **tak bisa** dikirim (UI + server); picker punya state no-result/error.
- [ ] Customer membuka product card → detail produk (`/products/{slug}`).
- [ ] Staff menulis catatan internal yang **tak pernah** terlihat customer.
- [ ] Staff mengubah status; badge unread **per-staff** benar. **Chat resolved: customer lihat pesan ramah + composer aktif; kirim pesan → auto-reopen & muncul lagi di tab staff.**
- [ ] Customer **tak** melihat jargon status mentah (`waiting_staff` dll).
- [ ] Staff membuka detail customer (nama, telp, order, total belanja, kesegaran).
- [ ] Customer tak dapat membaca chat customer lain / internal / catatan internal.
- [ ] **Karyawan tak bisa self-grant `canHandleCustomer`** (update **maupun** delete→recreate) — teruji emulator.
- [ ] Karyawan tanpa flag tak dapat akses Customer Inbox.
- [ ] Endpoint katalog, webhook, staff-send-image **terautentikasi**; upload tervalidasi (MIME+magic-byte).
- [ ] NLCATTER pagination; tak ada regresi chat internal (`notifyNewMessage` tetap `chats/**`).
- [ ] Security rules diuji; push dua arah tanpa PII.
- [ ] Auto-greeting (dalam jam) / auto-reply away (luar jam) — sekali, berlabel "Balasan otomatis"; header status online/away benar.
- [ ] Customer lihat typing; staff lain lihat banner "Sedang dibalas oleh {name}".
- [ ] Owner dapat menyalakan `canHandleCustomer` lewat toggle UI; owner dapat ubah jam operasional & pesan away.
- [ ] Kill-switch off → entry chat tersembunyi + composer nonaktif tanpa rilis ulang.
- [ ] Kegagalan webhook/FCM/proxy tercatat di log.

---

## 16. Berkas yang Terpengaruh (tingkat tinggi)

**`natalopetshopflutter/flutter_app/` (Natalo Flutter):** `widgets/app_chat_button.dart` (baru, badge dari `/api/chat/unread`); integrasi header (Beranda/Transaksi punya slot; Keranjang/Pesanan Saya/Detail Pesanan = action AppBar baru); `screens/chat_list_screen.dart` + `chat_room_screen.dart` (baru); `models/customer_chat*.dart` (baru); `services/chat_service.dart` (baru, REST); `state/chat_store.dart` (baru, cache per-`userId`); integrasi `product_detail_screen.dart`; **`services/deep_link_service.dart` (modify — case `/chat/{chatId}`)** + `push_notification_service.dart` (handler `customer_chat` + catch-up); route baru `main.dart`; iOS `Info.plist` `NSCameraUsageDescription` + Android `CAMERA`.

**`natalopetshopflutter/app/` (Next.js):** `api/chat/*` (proxy: room transaksional, send text/`send-image`→UploadThing, fetch allowlist, room-summary+`unread`, snapshot, jam WIB, auto-message), `api/chat/staff-send-image` (baru), `api/catalog/search` (auth §5.4), `api/chat/webhook` (shared-secret + dedupe), `api/chat/config` + mirror `app_settings/chatConfig`, integrasi Admin SDK tokochat + `verifyIdToken`, `lib/fcm.ts` (resolve `PushSubscription`), store rate-limit/idempotency (Prisma/Upstash), reuse `uploadToUT`/magic-byte. **Prisma `AppConfig`** (baru, kill-switch) — `ChatThread`/`ChatMessage` lama dibiarkan (mati).

**`NLCHAT/` (NLCATTER Flutter):** mode `isCustomer` di `screens/chat_screen.dart` (attach mode customer → `api/chat/staff-send-image`; tulis `typingStaff`; banner "sedang dibalas") + filter di `chat_list_screen.dart`, `screens/customer_product_picker.dart` (baru, +empty/error state), sheet detail customer, render catatan internal + auto-message + resolved/reopen copy, kontrol status, penolakan akses UI, **`screens/manage_users_screen.dart` (modify — toggle `canHandleCustomer`)**, `screens/chat_hours_settings_screen.dart` (baru), banner kill-switch (baca `app_settings/chatConfig`), `models/customer_chat*.dart` (baru), `functions/index.js` (`notifyNewCustomerMessage` recipients owner+flag + webhook push-balik + log §11c), `firestore.rules` (+`customerChats` + **guard `canHandleCustomer` immutable CREATE&UPDATE `users`**, §5.3), `firestore.indexes.json` (+index). (`storage.rules` tak berubah.)

---

## 17. Keputusan Terbuka / Risiko

- **Kredensial lintas-project & secret**: service account tokochat, shared-secret webhook, verifier catalog/upload — env Vercel, rotasi.
- **Konsistensi harga/stok**: snapshot katalog; validasi final saat checkout.
- **Kesegaran snapshot** = interaksi terakhir; refresh manual = lanjut.
- **Skala push staff**: broadcast ke owner + `canHandleCustomer`; banner "sedang dibalas" kurangi tabrakan. Tim CS besar → assignment (di luar MVP).
- **Tabel Prisma `ChatThread`/`ChatMessage` mati**: dibiarkan (tak menabrak); pembersihan = tahap lanjut. Firestore `customerChats` sumber tunggal.
- **Storage UploadThing** = URL publik tak-tertebak; +1 hop upload staff (NLCATTER→proxy→UploadThing). Signed-URL / presigned langsung = lanjut.
- **Kill-switch default fail-open**: outage config tak mematikan chat; off hanya via flag eksplisit.
