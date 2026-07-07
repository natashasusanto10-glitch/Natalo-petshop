# Customer Chat — Plan 4: Natalo App UI (Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membangun UI chat customer di app Natalo (Flutter, `flutter_app/`): ikon bubble ber-badge unread di header sebagai entry point, layar percakapan (gelembung customer/staff, kartu produk yang di-share staff, foto, pesan otomatis, status kirim), composer teks+kamera, polling near-realtime, dan perilaku kill-switch. Semua lewat REST proxy Plan 2 (Natalo TAK punya Firestore).

**Architecture:** Native Flutter. State via `ChangeNotifier` singleton (`chatStore`, pola `cartStore`). Jaringan lewat `apiClient` (`lib/services/api_client.dart`) — sesi `Bearer <User.id>` + `cookie member_session` sudah otomatis di `_headers()`. Tanpa Firestore listener → **polling** `GET /api/chat/{chatId}?after=<ts>` saat layar tampak + wake via `pushNotificationService.notificationRefreshTick` (pola `AppNotificationButton`). Kirim optimistic dgn `clientMsgId` (dedupe di proxy). Endpoint selaras Plan 2: `POST /api/chat/send`, `POST /api/chat/send-image`, `GET /api/chat/{chatId}` (sekaligus mark-read — Plan 2 Task 7), `GET /api/chat/unread`, `GET /api/chat/config`.

**Tech Stack:** Flutter, `http` (via `apiClient`), `image_picker` + `flutter_image_compress` (pola `feed_photo_service`), `ChangeNotifier`/`AnimatedBuilder`, `Timer.periodic` + `WidgetsBindingObserver`, tema `NataloColors`/`AppSpacing`/`AppRadius`, `flutter_test` (unit).

## Global Constraints

- Semua path relatif ke `flutter_app/` (repo Natalo `C:/Users/USER/Desktop/natalopetshopflutter`).
- **Reuse, jangan bikin baru:** `apiClient` (getJson/postJson/postMultipartFile), `AppHeaderIconButton` (`lib/widgets/app_ui.dart`), badge+pulse dari `AppCartButton` (`lib/widgets/app_cart_button.dart`), refresh via `pushNotificationService.notificationRefreshTick`, kompresi+upload dari `feed_photo_service.dart`, rute via `deep_link_service.dart` + `main.dart onGenerateRoute`.
- **Token warna WAJIB dari `NataloColors`** (primary `#1E5FBF`, primarySoft `#EEF4FF`, surface `#F8FAFC`, border `#E2E8F0`, danger `#EF4444`, success `#22C55E`, text `#0F172A/#475569/#94A3B8`). Radius `AppRadius.md`=12 untuk gelembung. Font PlusJakartaSans (dari tema, jangan set manual).
- **Keamanan:** UI TIDAK menegakkan apa pun — hanya render apa yang proxy kirim (proxy sudah allowlist projection: tak ada `internalNotes`/`staffOnly`). Jangan menaruh logika otorisasi di klien.
- **Kill-switch:** `GET /api/chat/config` → `{chatEnabled}`. `false` → sembunyikan `AppChatButton` + composer nonaktif ("Chat sedang dalam pemeliharaan"), riwayat tetap terbaca.
- **Widget test hati-hati (memori `flutter-widget-test-shimmer-hang`):** `pumpAndSettle` bisa hang bila gambar shimmer render. Untuk task ini utamakan **unit test** logika murni + verifikasi UI manual; bila menulis widget test, pakai bounded pump-loop, mock prefs, clear store, inject fetcher.
- Golden test pra-existing flaky (`natalo_colors`, `status_pill`) di luar cakupan — jangan dijadikan patokan hijau (memori `flutter-golden-tests-flaky`).
- Entry point header ADA di: Beranda, Keranjang, Transaksi, Pesanan Saya, Detail Pesanan — **TIDAK** di Akun (keputusan spec §7). Plus tombol chat di Detail Produk (menyisipkan `product_context`).

---

## File Structure

- `lib/models/chat_message.dart` — **create**: model `ChatMessage` (+ enum tipe/sender/status) & `ChatRoomState` + `fromJson`.
- `lib/state/chat_store.dart` — **create**: `ChatStore extends ChangeNotifier` (unread + config chatEnabled) singleton `chatStore`.
- `lib/services/chat_service.dart` — **create**: wrapper `apiClient` untuk send/sendImage/fetchMessages/fetchUnread/fetchConfig; util `newClientMsgId()`.
- `lib/widgets/app_chat_button.dart` — **create**: ikon bubble header + badge (pola `AppCartButton`).
- `lib/screens/chat_room_screen.dart` — **create**: layar percakapan + composer + polling.
- `lib/widgets/chat/*.dart` — **create**: `chat_bubble.dart`, `chat_product_card.dart`, `chat_image_message.dart`, `chat_system_note.dart`, `chat_composer.dart`.
- `lib/services/deep_link_service.dart` — **modify**: tambah case `chat` → buka `/chat`/`/chat/{chatId}`.
- `lib/main.dart` — **modify**: registrasi rute `/chat`.
- `lib/screens/{home,cart,transactions,member_orders,member_order_detail,product_detail}_screen.dart` — **modify**: sisipkan `AppChatButton` di `actions` (produk detail: tombol chat + `product_context`).
- `test/chat_message_test.dart`, `test/chat_store_test.dart`, `test/chat_service_test.dart` — **create**: unit test.

---

### Task 1: Model `ChatMessage` + parsing — TDD

**Files:**
- Test: `test/chat_message_test.dart`
- Create: `lib/models/chat_message.dart`

**Interfaces:**
- Produces: `ChatMessage.fromJson(Map)` toleran field opsional; enum `ChatSender {customer, staff}`, `ChatMsgType {text,image,product,productContext,orderContext,system}`, `ChatSendStatus {queued,sending,sent,failed}`. `ChatRoomState { status, messages, online }`.

- [ ] **Step 1: Tulis test yang gagal** (`test/chat_message_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo/models/chat_message.dart'; // cek name di pubspec

void main() {
  test('parse pesan teks staff', () {
    final m = ChatMessage.fromJson({
      'id': 'm1', 'senderRole': 'staff', 'type': 'text',
      'text': 'halo', 'createdAt': 1700000000000,
    });
    expect(m.sender, ChatSender.staff);
    expect(m.type, ChatMsgType.text);
    expect(m.text, 'halo');
  });

  test('parse kartu produk', () {
    final m = ChatMessage.fromJson({
      'id': 'm2', 'senderRole': 'staff', 'type': 'product',
      'product': {'productId': 'p1', 'name': 'RC Persian', 'price': 285000, 'stock': 8},
      'createdAt': 2,
    });
    expect(m.type, ChatMsgType.product);
    expect(m.product?.name, 'RC Persian');
    expect(m.product?.stock, 8);
  });

  test('tipe tak dikenal -> system (aman)', () {
    final m = ChatMessage.fromJson({'id': 'm3', 'type': 'weird', 'createdAt': 3});
    expect(m.type, ChatMsgType.system);
  });

  test('image message baca url', () {
    final m = ChatMessage.fromJson({
      'id': 'm4', 'senderRole': 'customer', 'type': 'image',
      'image': {'url': 'https://x/y.jpg'}, 'createdAt': 4,
    });
    expect(m.imageUrl, 'https://x/y.jpg');
    expect(m.sender, ChatSender.customer);
  });
}
```

- [ ] **Step 2: Jalankan — GAGAL.** Run: `flutter test test/chat_message_test.dart`.

- [ ] **Step 3: Implementasi `lib/models/chat_message.dart`** sesuai kontrak (enum + `fromJson` toleran; `product`/`order`/`image` sub-objek nullable; `clientMsgId` opsional; `status`/`auto` opsional).

- [ ] **Step 4: Jalankan — LULUS.**

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/chat_message.dart flutter_app/test/chat_message_test.dart
git commit -m "feat(chat): model ChatMessage + parsing toleran"
```

---

### Task 2: `ChatService` + `ChatStore` — TDD (logika murni)

**Files:**
- Test: `test/chat_service_test.dart`, `test/chat_store_test.dart`
- Create: `lib/services/chat_service.dart`, `lib/state/chat_store.dart`

**Interfaces:**
- `chat_service.dart`: `newClientMsgId()` → string valid (8–64 `[A-Za-z0-9_-]`, cocok `isValidClientMsgId` Plan 2); `mapMessages(List)` → `List<ChatMessage>`; wrapper `sendText/sendImage/fetchMessages/fetchUnread/fetchConfig` memakai `apiClient` (di-inject untuk test).
- `chat_store.dart`: `ChatStore extends ChangeNotifier` — `unreadCount`, `chatEnabled` (default true), `setUnread`, `applyConfig`, `fetchUnread()`, `fetchConfig()`; singleton `final chatStore = ChatStore()`.

- [ ] **Step 1: Test murni** — `newClientMsgId()` menghasilkan id valid & unik antar panggilan; `mapMessages` mengurutkan `createdAt` asc & buang entri tanpa id; `ChatStore.setUnread`/`applyConfig` memicu `notifyListeners` hanya saat nilai berubah; `fetchUnread`/`fetchConfig` dengan fake client mengisi state; error jaringan → state aman (unread tak berubah, chatEnabled tetap true = fail-open).

> Uji `ChangeNotifier` dgn menambah listener penghitung; jangan pakai timer nyata. Fake `apiClient` via parameter injeksi (`ChatService({ApiClientLike? client})`), bukan singleton global, agar teruji tanpa jaringan.

- [ ] **Step 2: Jalankan — GAGAL.**

- [ ] **Step 3: Implementasi** kedua file. `sendText` body `{text, clientMsgId, context?}`; `sendImage` via `apiClient.postMultipartFile('/api/chat/send-image', fieldName:'file', filePath:..., query:{clientMsgId})`; `fetchMessages(chatId, after)` → `GET /api/chat/$chatId?after=$after`; `fetchUnread` → `GET /api/chat/unread` (`{unreadForCustomer}`); `fetchConfig` → `GET /api/chat/config` (`{chatEnabled}`). Bungkus `ApiException` (isUnauthorized → propagasi ke UI untuk re-login).

- [ ] **Step 4: Jalankan — LULUS.**

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/chat_service.dart flutter_app/lib/state/chat_store.dart flutter_app/test/chat_service_test.dart flutter_app/test/chat_store_test.dart
git commit -m "feat(chat): ChatService (endpoint proxy) + ChatStore unread/config"
```

---

### Task 3: `AppChatButton` header + registrasi entry points

**Files:**
- Create: `lib/widgets/app_chat_button.dart`
- Modify: `lib/services/deep_link_service.dart`, `lib/main.dart`, dan 5 layar header + `product_detail_screen.dart`

**Interfaces:**
- Consumes: `AppHeaderIconButton`, `chatStore`, `pushNotificationService.notificationRefreshTick`.

- [ ] **Step 1: `AppChatButton`** — meniru `AppCartButton`: `AnimatedBuilder(animation: chatStore)`, ikon `Icons.chat_bubble_outline_rounded` (glyph 26), badge merah `#EF4444` `count>99?'99+':'$count'` posisi `top:6,right:6` (pola `app_cart_button.dart`), pulse saat naik. `onPressed` → `Navigator.pushNamed(context,'/chat')`. `initState`: daftar listener `notificationRefreshTick` → `chatStore.fetchUnread()`; hormati kill-switch: bila `!chatStore.chatEnabled` → `return const SizedBox.shrink()`.

- [ ] **Step 2: Rute** — `deep_link_service.dart` tambah `case 'chat':` (→ `/chat` atau `/chat/{chatId}` via arguments); `main.dart onGenerateRoute` tambah `'/chat'` → `ChatRoomScreen(chatId: null)` (resolusi chatId milik sesi di server) dan varian dgn argumen chatId.

- [ ] **Step 3: Sisipkan `AppChatButton`** ke `actions` di: `home_screen`, `cart_screen`, `transactions_screen`, `member_orders_screen`, `member_order_detail_screen`. **JANGAN** di layar Akun. Di `product_detail_screen`: tombol/ikon chat yang push `ChatRoomScreen` dgn argumen konteks produk (`{productId, slug}`) → dikirim sebagai `context` di pesan pertama (proxy menulis `product_context`).

- [ ] **Step 4: Verifikasi** — `flutter analyze lib/widgets/app_chat_button.dart lib/services/deep_link_service.dart` bersih; app build (`flutter build apk --debug` opsional) atau `flutter analyze` seluruh lib tanpa error baru.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/app_chat_button.dart flutter_app/lib/services/deep_link_service.dart flutter_app/lib/main.dart flutter_app/lib/screens/home_screen.dart flutter_app/lib/screens/cart_screen.dart flutter_app/lib/screens/transactions_screen.dart flutter_app/lib/screens/member_orders_screen.dart flutter_app/lib/screens/member_order_detail_screen.dart flutter_app/lib/screens/product_detail_screen.dart
git commit -m "feat(chat): AppChatButton header + entry points (5 layar + detail produk) + rute /chat"
```

---

### Task 4: `ChatRoomScreen` — gelembung, kartu produk, foto, composer

**Files:**
- Create: `lib/screens/chat_room_screen.dart`, `lib/widgets/chat/*.dart`

**Interfaces:**
- Consumes: Task 1–2. Widget potongan agar teruji/ringan: `ChatBubble`, `ChatProductCard`, `ChatImageMessage`, `ChatSystemNote`, `ChatComposer`.

- [ ] **Step 1: Layout dasar** (grounded ke tema & mockup):
  - AppBar putih border bawah `#E5EAF2`: avatar inisial "N" `primarySoft`, judul "Natalo Petshop" (18/w800), status: dot hijau `#22C55E` "Online" (dalam jam) / ikon jam "Di luar jam operasional".
  - Body `surface #F8FAFC`, `ListView` pesan (reverse atau auto-scroll ke bawah), padding `AppSpacing.lg`.
  - Gelembung **customer** kanan `primary #1E5FBF` teks putih, radius 14 (sudut kanan-atas 4); **staff** kiri putih border `#E2E8F0` teks `#0F172A`. Timestamp 10px `#94A3B8`; centang status (queued/sending=jam, sent=✓, dibaca=✓✓ `#1E5FBF`, failed=merah + tombol "Coba lagi").
  - `ChatSystemNote`: chip tengah "Balasan otomatis" (tag `primarySoft`/`primaryNavy`) untuk pesan `auto/system`.
  - `ChatProductCard`: kartu putih border, gambar (pakai `AppProductImage` yg ada), nama, harga `w800 #0F172A` + coret opsional, stok, tombol outline "Lihat Produk" → push detail produk.
  - `ChatImageMessage`: thumbnail rounded → fullscreen viewer.
  - `ChatComposer`: bar putih border atas, ikon `camera` (24, `#475569`), input pill `#F1F5F9` "Tulis pesan…", tombol kirim bundar `primary` (muncul saat ada teks/gambar).

- [ ] **Step 2: State resolved & kill-switch**
  - `status=='resolved'` → note ramah "Percakapan ditandai selesai. Kirim pesan lagi untuk melanjutkan." Composer tetap aktif; kirim lagi → optimistic (proxy set `waiting_staff`).
  - `!chatStore.chatEnabled` → composer diganti banner "Chat sedang dalam pemeliharaan" (read-only).
  - Empty state (belum ada pesan): ilustrasi + "Mulai percakapan dengan Natalo Petshop".

- [ ] **Step 3: Verifikasi manual (checklist)** — render tiap jenis pesan; kirim teks tampil optimistic; kartu produk → detail; foto → fullscreen; resolved & kill-switch benar. (Widget test opsional dgn caveat shimmer.)

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/screens/chat_room_screen.dart flutter_app/lib/widgets/chat/
git commit -m "feat(chat): ChatRoomScreen (gelembung, kartu produk, foto, composer, resolved, kill-switch)"
```

---

### Task 5: Kirim optimistic + foto + polling & lifecycle

**Files:**
- Modify: `lib/screens/chat_room_screen.dart`

**Interfaces:**
- Consumes: `chat_service` (send/sendImage/fetchMessages), `image_picker`+kompresi (pola `feed_photo_service`), `Timer.periodic`, `WidgetsBindingObserver`, `notificationRefreshTick`.

- [ ] **Step 1: Kirim teks optimistic** — buat `ChatMessage` lokal `status:queued` + `clientMsgId=newClientMsgId()`, tampilkan langsung, panggil `sendText`; sukses → rekonsiliasi via `clientMsgId` (ganti dgn versi server, `sent`); gagal → `failed` + tombol "Coba lagi" (kirim ulang `clientMsgId` sama → proxy dedupe).

- [ ] **Step 2: Kirim foto** — `image_picker` (kamera/galeri) → kompres (>1.5MB, quality 75, pola `feed_photo_service`) → optimistic thumbnail lokal → `sendImage`; error → `failed`.

- [ ] **Step 3: Polling & lifecycle**
  - `Timer.periodic(4s)` saat layar tampak → `fetchMessages(chatId, after: lastCreatedAt)` → append pesan baru (dedupe by id/clientMsgId), auto-scroll bila di bawah.
  - `WidgetsBindingObserver`: `paused` → hentikan timer; `resumed` → fetch sekali + mulai lagi. Listener `notificationRefreshTick` → fetch sekali (wake FCM).
  - Pull-to-refresh (`natalo_paw_refresh_indicator`) → fetch penuh.
  - GET `[chatId]` juga menandai baca di server (Plan 2 Task 7) → setelah fetch, `chatStore.setUnread(0)`.
  - `dispose`: batalkan timer + lepas observer/listener.

- [ ] **Step 4: Verifikasi manual** — dua device (atau NLCATTER balas) → pesan staff muncul ≤ ~4s; badge unread turun saat room dibuka; kirim saat offline → `failed` → retry sukses tanpa dobel.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/chat_room_screen.dart
git commit -m "feat(chat): kirim optimistic+retry, foto, polling 4s + lifecycle/wake"
```

---

## Definition of Done (Plan 4)

- [ ] Unit test hijau: `chat_message`, `chat_service`, `chat_store`.
- [ ] `flutter analyze` bersih untuk file baru/diubah (tanpa error baru).
- [ ] `AppChatButton` ber-badge unread tampil di 5 layar (bukan Akun) + tombol chat di detail produk; sembunyi saat kill-switch off.
- [ ] `ChatRoomScreen` merender semua jenis pesan (teks, foto, kartu produk, otomatis/system), composer teks+kamera, status kirim + retry, resolved & kill-switch.
- [ ] Polling 4s saat tampak, berhenti di background, wake via `notificationRefreshTick`; buka room → unread jadi 0.
- [ ] Warna/spasi/radius dari token `NataloColors`/`AppSpacing`/`AppRadius`; tak ada hardcode.
- [ ] UI tak menegakkan otorisasi (hanya render output proxy yang sudah ter-allowlist).

## Self-Review (penulis plan)

- **Grounding kode nyata:** `apiClient` (headers Bearer+cookie, getJson/postJson/postMultipartFile), `AppHeaderIconButton`, badge+pulse `AppCartButton`, `notificationRefreshTick`, kompresi `feed_photo_service`, rute `deep_link_service`/`main.dart`, token `NataloColors`/`AppRadius` — semua terverifikasi. ✓
- **Konsistensi lintas-plan:** endpoint selaras Plan 2 (GET `[chatId]` sekaligus mark-read; tak ada endpoint mark-read terpisah yang tak ada di Plan 2); `clientMsgId` cocok `isValidClientMsgId` Plan 2; kill-switch `GET /api/chat/config`. ✓
- **Keamanan:** klien tak menegakkan otorisasi; hanya render projeksi allowlist proxy; tak menyentuh data internal. ✓
- **Realtime:** polling (Natalo tanpa Firestore) + wake FCM — sesuai batasan arsitektur; FCM push dikirim CF→proxy (Plan 3), handler deep-link `/chat/{chatId}` sudah ada polanya. ✓
- **Risiko uji:** utamakan unit test; widget test dijaga caveat shimmer-hang & golden flaky (memori). Verifikasi UI utama = manual/dua-device.
- **Cakupan:** layar Akun sengaja tanpa entry (spec §7); auto-greeting/away hanya DITAMPILKAN (dibuat proxy, Plan 2), bukan diputuskan klien.
