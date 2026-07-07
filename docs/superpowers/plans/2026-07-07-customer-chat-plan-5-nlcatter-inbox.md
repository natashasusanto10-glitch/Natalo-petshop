# Customer Chat — Plan 5: NLCATTER Customer Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membangun **Customer Inbox** di NLCATTER (staff, repo NLCHAT): segmen "Customer" di daftar chat (baca `customerChats`), layar balas staff (gelembung, ringkasan customer, share kartu produk, catatan internal, status resolve/reopen, unread per-staff). Hanya untuk staff berhak (`owner || canHandleCustomer`). Semua visual mengikuti token NLCATTER (Roboto, `#0284C7`, `bubbleSent #DCF1FD`, `bgChat #E9F2F9`, `checkRead #34B7F1`, `GradientHeader`), TIDAK dicampur token Natalo.

**Architecture:** Sumber data = Firestore `customerChats` (project `tokochat-a8879`), diakses staff via SDK Firestore native (rules Plan 1: `canCS()`). Daftar = segmen baru di `chat_list_screen` yang menukar stream ke `customerChats` (filter status). Layar balas = `customer_chat_screen.dart` BARU yang **meniru styling** bubble/composer dari `chat_screen.dart` (jangan fork file 5000+ baris; ekstrak/duplikasi widget kecil bila perlu). Staff menulis pesan `senderRole:'staff'` → CF Plan 3 memicu FCM ke customer. Foto staff & katalog produk lewat **proxy Natalo** (endpoint di-auth Firebase ID token — bagian yang DITUNDA di Plan 2 §Deferred; jadi dependency Plan 5).

**Tech Stack:** Flutter, `cloud_firestore` (customerChats + subkoleksi messages/internalNotes), Provider/StreamBuilder (pola existing), `AppColors`/`AppRadius`/`AppSpacing`/`AppText` (`lib/utils/theme.dart`), `GradientHeader`, `flutter_test` (unit model).

## Global Constraints

- Semua path relatif ke root repo **NLCHAT** (`C:/Users/USER/Desktop/NLCHAT`).
- **Token WAJIB dari `AppColors`/`AppRadius`/`AppSpacing`/`AppText`** (build-sheet terverifikasi): font Roboto (default, jangan set custom); `primary #0284C7`, gradient header `#0284C7→#0369A1` (`GradientHeader`), `bubbleSent #DCF1FD`, `bubbleReceived/bgCard #FFFFFF`, `bgChat #E9F2F9` (latar percakapan + pill input), `bgScreen #F0F4F8` (list), `checkRead #34B7F1`, teks `textBody #111B21`/`textMeta #3D5064`/`textHint #51687A`, divider `borderLighter #E2E8F0`. Radius bubble `AppRadius.sm`=8 (sudut ekor 0), pill input `AppRadius.round`=20, badge unread pill r12.
- **Jangan fork `chat_screen.dart`** (5000+ baris, kopling ke skema `chats` internal). Buat `customer_chat_screen.dart` baru yang **meniru** gaya bubble/composer + reuse widget kecil (`GradientHeader`, `UserAvatar`, tombol) bila memungkinkan.
- **Gating akses:** seluruh permukaan Customer Inbox hanya tampil/terbuka bila `context.read<AuthProvider>().userProfile` = `owner` ATAU `canHandleCustomer == true`. Enforcement nyata = rules Plan 1 (`canCS()`); UI hanya menyembunyikan.
- **NO PING** di attach panel Customer Inbox (spec). Attach customer = Kamera · Foto · Bagikan Produk · Catatan Internal (tanpa Ping/Request/Tugas/Stok internal).
- **Catatan internal TAK PERNAH terkirim ke customer** — subkoleksi `internalNotes` terpisah; projeksi customer (proxy) tak menyertakannya. UI: kartu kuning "INTERNAL · HANYA STAFF".
- **Aturan stok:** produk `stock<=0` tak bisa di-share (picker disable + server tolak — dua lapis; lihat Plan 2/proxy).
- **Data sensitif:** jangan tampilkan/ekspor payroll/absensi/stok internal ke permukaan ini; hanya field ringkasan customer (nama, phone, totalBelanja, orderCount, lastOrder) dari room.
- **Dependencies:** Plan 1 (rules `canCS` di-deploy), Plan 3 (CF FCM), dan **endpoint proxy ter-auth-Firebase** (catalog/search + staff-send-image) yang DITUNDA di Plan 2 §Deferred — harus dibuat sebelum Task 4/foto staff berfungsi (flag di task terkait).
- Golden test flaky pra-existing di luar cakupan; widget test hati-hati (jaga hang shimmer) — utamakan unit test + verifikasi manual.

---

## File Structure

- `lib/models/customer_chat.dart` — **create**: `CustomerChatRoom`, `CustomerChatMessage`, `InternalNote` + `fromMap`.
- `lib/services/customer_chat_service.dart` — **create**: stream rooms (filter status), stream messages, stream internalNotes, kirim pesan staff, tambah note, ubah status, reset unread `unreadCount.{myUid}`, tulis `typingStaff` (throttle).
- `lib/screens/chat_list_screen.dart` — **modify**: tambah chip segmen "Semua · Customer · Internal · Grup"; saat "Customer", tukar stream ke `customerChats` + render tile customer.
- `lib/widgets/customer_chat_tile.dart` — **create**: tile daftar customer (avatar 52, nama 16/w700, preview 14/textMeta, tag "Natalo App", badge unread pill).
- `lib/screens/customer_chat_screen.dart` — **create**: layar balas (header ringkasan, gelembung, composer, attach panel tanpa PING, 3-dot menu, resolve/reopen).
- `lib/widgets/customer/*.dart` — **create**: `customer_bubble.dart`, `customer_product_card.dart`, `internal_note_card.dart`, `customer_summary_bar.dart`, `customer_composer.dart`.
- `test/customer_chat_model_test.dart` — **create**: unit test parsing + helper.

---

### Task 1: Model + service data layer — TDD (parsing) 

**Files:**
- Test: `test/customer_chat_model_test.dart`
- Create: `lib/models/customer_chat.dart`, `lib/services/customer_chat_service.dart`

**Interfaces:**
- `CustomerChatRoom.fromMap` (customerId, customerName, customerPhone, status, lastMessageText/Type/At, `unreadCount` map, unreadForCustomer, summary{totalBelanja,orderCount,lastOrder}, source, typingStaff). Getter `unreadFor(uid)`.
- `CustomerChatMessage.fromMap` (senderRole, senderName, type, text, image, product, order, auto, createdAt, status, readBy*). Enum aman untuk tipe.
- `InternalNote.fromMap` (authorId, authorName, text, createdAt).
- Service: fungsi murni `roomMatchesFilter(room, filter)` (open/waiting → tampil di Customer), `mediaLabel(msg)` (preview per tipe) yang teruji; sisanya stream Firestore.

- [ ] **Step 1: Tulis test yang gagal** — parsing room/message/note; `unreadFor('me')` benar; `mediaLabel` ("📷 Foto"/"Produk"/teks); `roomMatchesFilter` (resolved tak muncul di tab aktif kecuali filter "Semua").

- [ ] **Step 2: Jalankan — GAGAL.** `flutter test test/customer_chat_model_test.dart`.

- [ ] **Step 3: Implementasi** model + service (stream pakai `FirebaseFirestore.instance.collection('customerChats')...`; query `where('status', whereIn: [...]).orderBy('lastMessageAt', descending:true)` — butuh index Plan 1 Task 5).

- [ ] **Step 4: Jalankan — LULUS.**

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add lib/models/customer_chat.dart lib/services/customer_chat_service.dart test/customer_chat_model_test.dart
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(customer-inbox): model + service data layer customerChats"
```

---

### Task 2: Segmen "Customer" di daftar + `CustomerChatTile`

**Files:**
- Modify: `lib/screens/chat_list_screen.dart`
- Create: `lib/widgets/customer_chat_tile.dart`

**Interfaces:**
- Consumes: `customer_chat_service` (stream rooms), `AuthProvider` (gating), token AppColors.

- [ ] **Step 1: Chip segmen** — di `chat_list_screen`, tambah baris chip "Semua · Customer · Internal · Grup" (pola chip: radius 99, aktif `primary` bg + teks putih, non-aktif `bgChat` + `textBody`, 13/w600, pad 6×13). Chip "Customer" hanya muncul bila staff berhak (`owner||canHandleCustomer`).

- [ ] **Step 2: Tukar stream** — saat segmen "Customer": tampilkan `StreamBuilder` dari `customer_chat_service.streamRooms(filter)` alih-alih daftar `chats` internal; render `CustomerChatTile`. Segmen lain tetap perilaku existing.

- [ ] **Step 3: `CustomerChatTile`** (grounded build-sheet):
  - Padding `16×12`; avatar 52 lingkaran `bgIndigo #E0F2FE` + inisial nama `primary`; margin kanan 12; divider 1px `borderLighter` indent 80.
  - Baris1: nama 16/w700 `textBody` (ellipsis) + timestamp 12 `textHint` kanan (format Hari ini=HH.mm, Kemarin, dd/MM/yy).
  - Baris2: preview 14 `textMeta` (ellipsis) atau typing "sedang mengetik…" 14/w600 italic `successDark` bila customer mengetik; badge unread pill (`primary` bg, putih 11/w700, r12, pad 7×2, margin kiri 8) dari `unreadFor(myUid)`.
  - Tag "Natalo App": chip halus `bgIndigo`/`#0369A1` 10/w700 r6 (subtle — konsisten memori badge).

- [ ] **Step 4: Verifikasi** — `flutter analyze` bersih; verifikasi manual daftar customer muncul untuk owner/CS, tersembunyi untuk karyawan biasa.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add lib/screens/chat_list_screen.dart lib/widgets/customer_chat_tile.dart
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(customer-inbox): segmen Customer di daftar + CustomerChatTile"
```

---

### Task 3: `CustomerChatScreen` — header ringkasan, gelembung, composer

**Files:**
- Create: `lib/screens/customer_chat_screen.dart`, `lib/widgets/customer/*.dart`

**Interfaces:**
- Consumes: Task 1 service (stream messages, kirim staff message, reset unread), token AppColors, `GradientHeader`.

- [ ] **Step 1: Header + ringkasan customer**
  - `GradientHeader`-style biru: back, avatar 40 + nama customer 17/w700 putih, status ("Menunggu balasan" + dot). Kanan: **3-dot** (tanpa PING). Menu: Ubah status · Tambah catatan internal · Media · Bisukan notifikasi (tanpa Assign).
  - `CustomerSummaryBar` di bawah header (putih border bawah `borderLighter`): "Total belanja Rp… · N pesanan · Terakhir INV… " + chip status order (mis. PAID `bgGreen`/`successDark`). Data dari room.summary.

- [ ] **Step 2: Daftar pesan** (latar `bgChat #E9F2F9`)
  - `CustomerBubble`: **staff (kanan)** `bubbleSent #DCF1FD`; **customer (kiri)** `bgCard` putih; radius `AppRadius.sm`=8 (sudut ekor 0); pad 12×8; teks 15 `textBody`; shadow `black .06 blur 1`; timestamp inline 10 `textHint`; centang staff ✓/✓✓ (`checkRead #34B7F1`, ✓✓ w700).
  - `InternalNoteCard` (dari stream internalNotes): kartu `bgYellow #FEF3C7` border, badge "INTERNAL · HANYA STAFF" (`#92400E`), teks note — HANYA di sisi staff, tak pernah dikirim ke customer.
  - Pesan `auto/system`: catatan tengah (chip) — label "Balasan otomatis" bila `auto`.
  - `reset unread`: saat layar dibuka, `customer_chat_service.resetUnread(chatId, myUid)` → `unreadCount.{myUid}=0`.

- [ ] **Step 3: Composer** (`CustomerComposer`, grounded _inputBar)
  - Container putih pad `4L/5TB/8R`; leading `add_circle_outline` 26 `textMeta` (buka attach panel) + `emoji_emotions_outlined` 25 `textMeta`; pill input `bgChat` r20 pad 14×9 hint "Ketik pesan…"; trailing morph: **send** (lingkaran `primary` 38, `send_rounded` putih 20) saat ada teks / **camera** (`photo_camera_rounded` 25 `textMeta`) saat kosong.
  - Kirim → `customer_chat_service.sendStaffText(chatId, text)` (tulis `senderRole:'staff'`, `senderName`, update lastMessage*). CF Plan 3 memicu FCM customer.
  - Tulis `typingStaff` throttle ~3s saat mengetik (koordinasi antar-staff).

- [ ] **Step 4: Verifikasi manual** — buka room dari daftar → pesan tampil; kirim balasan → muncul kanan; unread badge daftar jadi 0; catatan internal tampil hanya di staff.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add lib/screens/customer_chat_screen.dart lib/widgets/customer/
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(customer-inbox): CustomerChatScreen (ringkasan, gelembung, catatan internal, composer)"
```

---

### Task 4: Attach panel (tanpa PING) + Bagikan Produk + foto staff

> **Dependency:** endpoint proxy ter-auth-Firebase (`GET /api/catalog/search`, `POST /api/chat/staff-send-image`) — DITUNDA di Plan 2 §Deferred. Buat dulu (verifikasi ID token staff + cek `canHandleCustomer`) sebelum task ini fungsional end-to-end.

**Files:**
- Modify: `lib/screens/customer_chat_screen.dart`; Create: `lib/widgets/customer/customer_product_card.dart`, product picker sheet.

- [ ] **Step 1: Attach panel** — grid 4-kolom (pad 12/18/12, tile lingkaran 52 `color.withAlpha(.12)`, ikon 24, label 11 `textMeta`): **Kamera** (`primary`), **Foto** (#7C3AED), **Bagikan Produk** (`info #3B82F6`), **Catatan Internal** (`warningDark`). **TIDAK ada** Ping/Request/Tugas/Stok internal.

- [ ] **Step 2: Bagikan Produk** — picker: query `GET /api/catalog/search` (via ID token staff). Item `stock<=0` **disable** (dim + "Stok habis", tak bisa dipilih). Pilih produk → kirim pesan `type:'product'` (server juga menolak `stock<=0` — dua lapis). `CustomerProductCard` render di gelembung: gambar, nama, harga w800 + coret, stok, tombol "Lihat Produk" → deep link `/products/{slug}` di customer.

- [ ] **Step 3: Foto staff** — Kamera/Foto → upload via `POST /api/chat/staff-send-image` (proxy → UploadThing, Rev 5) → pesan `type:'image'`. (Storage Firebase `customer_chat_images` = fallback tak terpakai per Rev 5.)

- [ ] **Step 4: Catatan Internal** — sheet input → `customer_chat_service.addInternalNote(chatId, text)` (tulis `internalNotes/{id}`; immutable). Muncul sebagai `InternalNoteCard`.

- [ ] **Step 5: Verifikasi manual** — share produk ready → kartu muncul di customer; produk habis → tak bisa di-share; foto terkirim; catatan internal tak terlihat customer (cek app Natalo).

- [ ] **Step 6: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add lib/screens/customer_chat_screen.dart lib/widgets/customer/
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(customer-inbox): attach (tanpa PING) + bagikan produk (guard stok) + foto + catatan internal"
```

---

### Task 5: Status resolve/reopen + koordinasi typingStaff

**Files:**
- Modify: `lib/screens/customer_chat_screen.dart`, `lib/services/customer_chat_service.dart`

- [ ] **Step 1: Ubah status** (3-dot → Ubah status): Open → Menunggu customer → Menunggu staff → **Selesai (resolved)**. Transisi `waiting_*` = tulis pesan `staffOnly:true` (tak jadi bubble customer). `resolved` = tulis pesan `system` ramah-customer ("Percakapan ditandai selesai. Kirim pesan lagi kapan saja."). Update `status`, `statusChangedBy/At`.

- [ ] **Step 2: Reopen otomatis** — (di sisi proxy/CF saat pesan customer masuk ke room resolved → set `waiting_staff` + bubble "Percakapan dibuka kembali"). Di UI: tampilkan status terkini; jika `resolved`, banner kecil di atas composer "Ditandai selesai — balas untuk membuka lagi".

- [ ] **Step 3: typingStaff banner** — bila `typingStaff` room diisi staff LAIN (uid ≠ myUid, umur <10s), tampilkan banner "Sedang dibalas oleh {name}" di atas composer (cegah dobel-balas). Composer lokal menulis `typingStaff` (Task 3 Step 3); auto-clear >10s.

- [ ] **Step 4: Verifikasi manual** — ubah ke Selesai → bubble system muncul di customer; customer balas → room reopen `waiting_staff`; dua staff buka room → yang satu lihat "Sedang dibalas oleh …".

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add lib/screens/customer_chat_screen.dart lib/services/customer_chat_service.dart
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(customer-inbox): status resolve/reopen + banner koordinasi typingStaff"
```

---

## Definition of Done (Plan 5)

- [ ] Unit test model/service hijau (`customer_chat_model_test`).
- [ ] `flutter analyze` bersih untuk file baru/diubah.
- [ ] Segmen "Customer" di daftar hanya untuk `owner||canHandleCustomer`; tile menampilkan tag "Natalo App" + unread `unreadCount.{myUid}`.
- [ ] `CustomerChatScreen`: ringkasan customer, gelembung (staff `bubbleSent`/customer putih, ✓✓ `checkRead`), catatan internal kuning (hanya staff), composer (add/emoji/pill/send-camera morph), attach **tanpa PING**.
- [ ] Bagikan produk hormati stok (dua lapis); foto staff via proxy; catatan internal tak pernah ke customer.
- [ ] Status resolve/reopen + banner "Sedang dibalas oleh …"; buka room reset unread staff.
- [ ] Semua warna/spacing/radius/ikon/font dari token NLCATTER (Roboto, `#0284C7`, dst.) — nol hardcode, nol token Natalo.

## Self-Review (penulis plan)

- **Grounding source (build-sheet terverifikasi):** token `AppColors`/`AppRadius`/`AppSpacing`/`AppText`, `GradientHeader`, struktur tile (`chat_list_screen.dart:723–1019`), bubble & composer (`chat_screen.dart:4908–5063, 5930–6020`), attach panel (`chat_screen.dart:4001–4042`), font Roboto — semua diverifikasi ulang ke file. ✓
- **Konsistensi lintas-plan:** unread per-staff `unreadCount.{uid}` di-increment CF (Plan 3), di-reset saat staff buka room (di sini); `internalNotes`/`staffOnly` tak pernah ke customer (allowlist proxy Plan 2); kirim staff → CF webhook FCM (Plan 3); produk/ foto lewat endpoint proxy ter-auth-Firebase (Plan 2 §Deferred — flagged sebagai dependency Task 4). ✓
- **Keamanan:** gating `canHandleCustomer` (UI + rules Plan 1); tak mengekspos payroll/absensi/stok internal; guard stok share dua lapis. ✓
- **Fidelity:** dilarang fork `chat_screen.dart`; `customer_chat_screen.dart` baru meniru gaya; token 100% NLCATTER, tak dicampur Natalo (memori `mockup-fidelity-per-app`). ✓
- **Batas uji:** unit test model/service; interaksi Firestore/stream & UI diverifikasi manual (widget test dijaga caveat shimmer/golden flaky).
- **Dependency terbuka:** endpoint proxy `catalog/search` + `staff-send-image` (Plan 2 §Deferred) harus dibuat sebelum Task 4 end-to-end — ditandai eksplisit.
