# Customer Chat — Plan 3: Cloud Functions tokochat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menambah Cloud Function di NLCATTER (`tokochat-a8879`, repo NLCHAT/functions) yang menutup lingkar realtime: saat pesan baru masuk ke `customerChats/{chatId}/messages`, sistem (a) memberi tahu **staff** yang berhak (FCM) + menaikkan unread per-staff saat pesan dari **customer**, dan (b) memanggil **webhook proxy Natalo** (HMAC) + menaikkan `unreadForCustomer` saat pesan dari **staff**, sehingga customer menerima notifikasi FCM di app Natalo.

**Architecture:** Satu trigger `onDocumentCreated` pada `customerChats/{chatId}/messages/{messageId}` bercabang berdasarkan `senderRole`. CF berjalan di `tokochat-a8879` (punya akses `users` untuk hitung staff berhak = `owner || canHandleCustomer`, dan menulis `customerChats`). Webhook keluar ke Natalo proxy memakai **shared-secret HMAC** yang **sama** dengan Plan 2 (`CHAT_WEBHOOK_SECRET`). Auto-greeting/away **bukan** tanggung jawab CF (itu proxy, spec §4.5–4.6) → plan ini sengaja tak menyentuh jam operasional.

**Tech Stack:** firebase-functions **v2** (`firebase-functions/v2/firestore` `onDocumentCreated`, `firebase-functions/params` `defineSecret`), firebase-admin v13 (`getFirestore`, `getMessaging`, `FieldValue`), Node.js 22 (CommonJS), `fetch` (bundled via firebase-admin) + `crypto` (HMAC), Node built-in test runner (`node --test`).

## Global Constraints

- Region **`asia-southeast1`** untuk semua fungsi (100% konsisten di repo).
- **v2 API + CommonJS** (`require`), meniru `exports.notifyNewMessage` (`functions/index.js`).
- FCM ke staff: token di `users/{uid}.fcmTokens` (array); kirim `getMessaging().sendEachForMulticast(...)`; bersihkan token mati dgn `FieldValue.arrayRemove(...)` untuk kode `registration-token-not-registered|invalid-registration-token|invalid-argument` — pola identik `notifyNewMessage` (index.js ~L460–484).
- **Idempotensi:** trigger fire-sekali per pesan; retry CF ditoleransi karena webhook proxy sudah dedupe `messageId` (Plan 2 Task 8). Increment unread pakai `FieldValue.increment(1)` (tak idempoten pada retry — diterima; alternatif dedupe via subdoc `notified/{messageId}` bila perlu, opsional Step di Task 3).
- **Webhook contract (SATU sumber kebenaran, samakan dgn Plan 2 Task 8):**
  - Method `POST` ke `${NATALO_PROXY_BASE_URL}/api/chat/webhook`.
  - Header `x-chat-signature` = `HMAC_SHA256(rawBody, CHAT_WEBHOOK_SECRET)` hex.
  - Body JSON: `{ chatId, customerUserId, messageId, preview, senderName }`.
  - `rawBody` yang ditandatangani = string JSON persis yang dikirim (jangan re-serialize beda).
- **Secret:** `CHAT_WEBHOOK_SECRET` via `defineSecret` (di-set `firebase functions:secrets:set CHAT_WEBHOOK_SECRET`, nilai **sama** dgn env Natalo). Base URL `NATALO_PROXY_BASE_URL` non-secret via `functions/.env` (gitignored). Nilai hardcode fallback hanya untuk non-sensitif.
- **Reconciliation lintas-plan (WAJIB):** kepemilikan unread dipindah agar tak dobel:
  - **CF** memiliki `unreadCount.{staffUid}` (increment saat pesan customer) dan `unreadForCustomer` (increment saat pesan staff).
  - **Proxy (Plan 2)** hanya mereset: `unreadForCustomer=0` saat customer buka (Task 7). **Hapus** increment per-staff dari `writeCustomerMessage` Plan 2 Task 4 (proxy tak tahu daftar staff tokochat). Catat penyesuaian ini saat eksekusi Plan 2. Reset `unreadCount.{uid}` saat staff buka room = tanggung jawab NLCATTER inbox (Plan 5).
- Deploy CF = tahap terpisah (`firebase deploy --only functions:notifyNewCustomerMessage`) sesudah review; JANGAN deploy dalam plan ini.
- Semua path relatif ke root repo **NLCHAT** (`C:/Users/USER/Desktop/NLCHAT`).

---

## File Structure

- `functions/chat/customerChat.js` — **create**: fungsi murni (routing senderRole, filter staff berhak, builder payload FCM & webhook, HMAC sign).
- `functions/test/customerChat.test.js` — **create**: uji fungsi murni via `node --test`.
- `functions/package.json` — **modify**: tambah script `"test": "node --test test/"`.
- `functions/index.js` — **modify**: tambah `exports.notifyNewCustomerMessage` (trigger + wiring efek samping).
- `functions/.env` — **create (gitignored)**: `NATALO_PROXY_BASE_URL=...`.
- `functions/.gitignore` — **modify/verify**: pastikan `.env` diabaikan.

---

### Task 1: Fungsi murni + harness test (`functions/chat/customerChat.js`) — TDD

**Files:**
- Create: `functions/chat/customerChat.js`
- Create: `functions/test/customerChat.test.js`
- Modify: `functions/package.json` (script test)

**Interfaces:**
- Produces (semua murni, tanpa I/O Firestore/FCM):
  - `classifyMessage(msg)` → `{ notifyStaff: bool, notifyCustomer: bool }`. Aturan: `staffOnly===true` → keduanya false; `type==='system'` → keduanya false; `senderRole==='customer'` → `{notifyStaff:true, notifyCustomer:false}`; `senderRole==='staff'` → `{notifyStaff:false, notifyCustomer:true}`.
  - `filterEligibleStaff(userDocs)` → array uid, dari doc `users` yang `role==='owner' || canHandleCustomer===true`.
  - `buildStaffFcmPayload({chatId, senderName, preview})` → objek `{notification, data, android, apns}` (data: `type:'customer_chat'`, `chatId`, `deepLink:'/chat/'+chatId`; TANPA PII selain nama pengirim & preview singkat).
  - `buildWebhookPayload({chatId, customerUserId, messageId, text, type, senderName})` → `{chatId, customerUserId, messageId, preview, senderName}` (preview = `previewText(text, type)`).
  - `previewText(text, type)` → untuk `image` = `'📷 Foto'`, `product*`/`order*` = ringkas, `text` = potong ≤ 120 char.
  - `customerUserIdFromChat(chatId, roomCustomerId)` → `roomCustomerId` bila ada, else `chatId.replace(/^cust_/, '')`.
  - `signWebhook(rawBody, secret)` → HMAC-SHA256 hex (`crypto`).

- [ ] **Step 1: Tambah script test ke `functions/package.json`**

Di `"scripts"`, tambah: `"test": "node --test test/"`. (Node 22 punya test runner bawaan; tak perlu dependency baru.)

- [ ] **Step 2: Tulis test yang gagal — `functions/test/customerChat.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {
  classifyMessage, filterEligibleStaff, buildWebhookPayload,
  previewText, customerUserIdFromChat, signWebhook,
} = require("../chat/customerChat");

test("classify: pesan customer -> notify staff saja", () => {
  assert.deepEqual(classifyMessage({ senderRole: "customer", type: "text" }),
    { notifyStaff: true, notifyCustomer: false });
});
test("classify: pesan staff -> notify customer saja", () => {
  assert.deepEqual(classifyMessage({ senderRole: "staff", type: "text" }),
    { notifyStaff: false, notifyCustomer: true });
});
test("classify: staffOnly & system -> diam", () => {
  assert.deepEqual(classifyMessage({ senderRole: "staff", type: "text", staffOnly: true }),
    { notifyStaff: false, notifyCustomer: false });
  assert.deepEqual(classifyMessage({ senderRole: "staff", type: "system" }),
    { notifyStaff: false, notifyCustomer: false });
});

test("filterEligibleStaff: owner + canHandleCustomer", () => {
  const docs = [
    { id: "o1", data: () => ({ role: "owner" }) },
    { id: "cs1", data: () => ({ role: "karyawan", canHandleCustomer: true }) },
    { id: "k1", data: () => ({ role: "karyawan" }) },
    { id: "k2", data: () => ({ role: "karyawan", canHandleCustomer: false }) },
  ];
  assert.deepEqual(filterEligibleStaff(docs).sort(), ["cs1", "o1"]);
});

test("previewText ringkas per tipe", () => {
  assert.equal(previewText("", "image"), "📷 Foto");
  assert.equal(previewText("x".repeat(200), "text").length <= 121, true);
});

test("customerUserIdFromChat: pakai roomCustomerId lalu fallback strip prefix", () => {
  assert.equal(customerUserIdFromChat("cust_abc", "abc"), "abc");
  assert.equal(customerUserIdFromChat("cust_abc", undefined), "abc");
});

test("buildWebhookPayload bentuk sesuai kontrak Plan 2 Task 8", () => {
  const p = buildWebhookPayload({
    chatId: "cust_abc", customerUserId: "abc", messageId: "m1",
    text: "halo", type: "text", senderName: "Sisca",
  });
  assert.deepEqual(Object.keys(p).sort(),
    ["chatId", "customerUserId", "messageId", "preview", "senderName"]);
  assert.equal(p.preview, "halo");
});

test("signWebhook cocok dgn HMAC referensi", () => {
  const body = JSON.stringify({ a: 1 });
  const expected = crypto.createHmac("sha256", "s").update(body).digest("hex");
  assert.equal(signWebhook(body, "s"), expected);
});
```

- [ ] **Step 3: Jalankan — pastikan GAGAL**

Run (dari `functions/`): `npm test`
Expected: gagal impor `../chat/customerChat`.

- [ ] **Step 4: Implementasi `functions/chat/customerChat.js`**

Implementasikan semua fungsi murni sesuai kontrak test (CommonJS `module.exports = {...}`). `buildStaffFcmPayload` mengembalikan struktur meniru `notifyNewMessage` (android priority high + collapseKey chatId, apns collapse-id chatId).

- [ ] **Step 5: Jalankan — pastikan LULUS**

Run (dari `functions/`): `npm test`
Expected: semua test PASS.

- [ ] **Step 6: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add functions/chat/customerChat.js functions/test/customerChat.test.js functions/package.json
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(functions): helper murni customer-chat (routing, staff berhak, payload, HMAC)"
```

---

### Task 2: Trigger + cabang pesan CUSTOMER (notify staff + unread per-staff)

**Files:**
- Modify: `functions/index.js`

**Interfaces:**
- Consumes: helper Task 1, `getFirestore`, `getMessaging`, `FieldValue` (sudah diimpor di index.js).

- [ ] **Step 1: Tambah kerangka `exports.notifyNewCustomerMessage`**

Di `functions/index.js`, tambahkan (meniru `notifyNewMessage`):

```js
exports.notifyNewCustomerMessage = onDocumentCreated(
  { document: "customerChats/{chatId}/messages/{messageId}", region: "asia-southeast1" },
  async (event) => {
    const msg = event.data && event.data.data();
    if (!msg) return;
    const { chatId, messageId } = event.params;
    const { notifyStaff, notifyCustomer } = classifyMessage(msg);
    if (!notifyStaff && !notifyCustomer) return;

    const db = getFirestore();
    const roomRef = db.doc(`customerChats/${chatId}`);

    if (notifyStaff) {
      // cabang pesan CUSTOMER (Task 2)
    }
    if (notifyCustomer) {
      // cabang pesan STAFF (Task 3)
    }
  }
);
```
Pastikan `classifyMessage` (dan helper lain) di-`require` di atas index.js: `const { classifyMessage, filterEligibleStaff, buildStaffFcmPayload, buildWebhookPayload, customerUserIdFromChat, signWebhook, previewText } = require("./chat/customerChat");`

- [ ] **Step 2: Isi cabang CUSTOMER**
- Query `db.collection('users').get()` → `filterEligibleStaff(snap.docs)` → daftar uid berhak.
- `unreadCount` increment: `roomRef.set({ unreadCount: Object.fromEntries(uids.map(u => [u, FieldValue.increment(1)])) }, { merge: true })` (map merge; `senderId` staff yang sedang tak relevan karena ini pesan customer).
- Kumpulkan token: baca `fcmTokens` tiap staff berhak (dari doc yang sudah di-`get`), gabung + map token→uid.
- `getMessaging().sendEachForMulticast(buildStaffFcmPayload({ chatId, senderName: msg.senderName || 'Customer', preview: previewText(msg.text, msg.type) }) + { tokens })` — susun objek final dgn `tokens`.
- Bersihkan token mati (pola `arrayRemove` seperti `notifyNewMessage`).
- Log JSON terstruktur (`logj("INFO","notifyNewCustomerMessage","staff_notified",{chatId, count})`).

- [ ] **Step 3: Verifikasi lint/parse**

Run (dari `functions/`): `node -c index.js` (cek sintaks) — Expected: tak ada SyntaxError. (Uji logika inti sudah di Task 1; efek Firestore/FCM diverifikasi saat emulator/integrasi Plan 5.)

- [ ] **Step 4: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add functions/index.js
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(functions): notifyNewCustomerMessage cabang customer (FCM staff + unread per-staff)"
```

---

### Task 3: Cabang pesan STAFF (webhook HMAC ke proxy + unreadForCustomer) + secret

**Files:**
- Modify: `functions/index.js`
- Create: `functions/.env` (gitignored), verify `functions/.gitignore`

**Interfaces:**
- Consumes: `buildWebhookPayload`, `signWebhook`, `customerUserIdFromChat` (Task 1); `defineSecret`.

- [ ] **Step 1: Deklarasi secret + env**
- Di atas index.js: `const { defineSecret } = require("firebase-functions/params"); const CHAT_WEBHOOK_SECRET = defineSecret("CHAT_WEBHOOK_SECRET");`
- Tambah `secrets: [CHAT_WEBHOOK_SECRET]` ke opsi `onDocumentCreated` `notifyNewCustomerMessage`.
- `functions/.env`: `NATALO_PROXY_BASE_URL=https://natalopetshop.com` (sesuaikan domain proxy). Pastikan `.env` ada di `functions/.gitignore`.

- [ ] **Step 2: Isi cabang STAFF**
- Baca room: `const room = (await roomRef.get()).data() || {};`
- `unreadForCustomer` increment: `roomRef.set({ unreadForCustomer: FieldValue.increment(1) }, { merge: true })`.
- Susun payload: `const customerUserId = customerUserIdFromChat(chatId, room.customerId); const payload = buildWebhookPayload({ chatId, customerUserId, messageId, text: msg.text, type: msg.type, senderName: msg.senderName || 'Natalo' });`
- `const raw = JSON.stringify(payload); const sig = signWebhook(raw, CHAT_WEBHOOK_SECRET.value());`
- POST: `fetch(`${process.env.NATALO_PROXY_BASE_URL}/api/chat/webhook`, { method:'POST', headers:{ 'Content-Type':'application/json', 'x-chat-signature': sig }, body: raw })`.
- **Jangan `throw`** bila webhook gagal — log ERROR terstruktur & return (pesan sudah tersimpan; FCM customer best-effort). Timeout/try-catch wajib.

- [ ] **Step 3: (Opsional) dedupe increment via subdoc**
Bila mau increment idempoten terhadap retry CF: sebelum increment, `create` doc `customerChats/{chatId}/notified/{messageId}` dalam transaksi; bila sudah ada → skip. Catat sebagai opsional (biaya 1 write; retry CF jarang).

- [ ] **Step 4: Verifikasi parse**

Run (dari `functions/`): `node -c index.js` → tak ada SyntaxError. `npm test` → helper tetap hijau.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add functions/index.js functions/.gitignore
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(functions): cabang staff -> webhook HMAC proxy Natalo + unreadForCustomer"
```

---

## Definition of Done (Plan 3)

- [ ] `npm test` di `functions/` hijau (helper murni: classify, filter, payload, HMAC).
- [ ] `node -c functions/index.js` tanpa SyntaxError; `notifyNewCustomerMessage` ter-ekspor, region `asia-southeast1`, `secrets:[CHAT_WEBHOOK_SECRET]`.
- [ ] Cabang customer: notify staff berhak (`owner||canHandleCustomer`) via FCM + increment `unreadCount.{uid}`; token mati dibersihkan.
- [ ] Cabang staff: webhook `POST /api/chat/webhook` dgn header `x-chat-signature` + body kontrak Plan 2 Task 8; increment `unreadForCustomer`; gagal webhook = log, bukan throw.
- [ ] `staffOnly`/`system` tak memicu FCM arah mana pun.
- [ ] Secret `CHAT_WEBHOOK_SECRET` via `defineSecret`; base URL via `functions/.env` (gitignored).
- [ ] Tak ada `firebase deploy` dijalankan.

## Self-Review (penulis plan)

- **Grounding kode nyata:** trigger `onDocumentCreated`+region, FCM `sendEachForMulticast`+`arrayRemove` cleanup, `logj` structured log, `fetch` bundled, `process.env`/`defineSecret` — semua terverifikasi di `functions/index.js` & `functions/package.json`. ✓
- **Konsistensi lintas-plan:** webhook contract (header `x-chat-signature`, body `{chatId,customerUserId,messageId,preview,senderName}`) disamakan dgn Plan 2 Task 8; kepemilikan unread dipindah ke CF dgn catatan penyesuaian Plan 2 Task 4 & Plan 5. ✓
- **Batas cakupan:** auto-greeting/away sengaja TIDAK di CF (proxy, spec §4.5–4.6); status transitions bukan CF (proxy/UI). ✓
- **Keamanan:** payload FCM staff & customer tanpa PII sensitif (hanya nama pengirim + preview + deepLink); webhook ber-HMAC; CF tak mengekspos koleksi internal. ✓
- **Batas uji:** logika murni teruji `node --test`; efek Firestore/FCM/HTTP nyata diverifikasi saat integrasi (emulator/Plan 5), konsisten gaya repo tanpa mock berat.
- **Idempotensi:** dijelaskan (proxy dedupe messageId; opsi subdoc `notified/` untuk increment).
