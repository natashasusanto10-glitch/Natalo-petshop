# Customer Chat — Plan 1: Fondasi Data & Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **STATUS (2026-07-07): EXECUTED & MERGED ke NLCHAT `main`** (merge commit `6c384b4`; 34/34 uji emulator hijau; lolos review per-task + whole-branch opus). **Belum `firebase deploy`** (di-gate, menunggu persetujuan). Rules yang di-ship **lebih ketat** dari draf awal (hardening yang kamu setujui saat review): (a) `customerChats` root `update` dibatasi **field allowlist**; (b) root `create: if false` (room = proxy Admin SDK saja); (c) `messages` `create` wajib `senderRole=='staff'` + `update` dikunci ke penanda baca (anti-forgery, konten immutable). **Task 7 `app_settings`**: rule-nya ternyata **sudah ada** (dari attendance) → yang ditambah cuma test + komentar. Test runner di-serialkan (`--test-concurrency=1`). Blok rules di Task 2 & Task 7 di bawah sudah diperbarui agar cocok dengan yang di-ship.

**Goal:** Menegakkan lapisan keamanan Firestore/Storage untuk fitur chat customer di project `tokochat-a8879` (repo `NLCHAT`), lengkap dengan harness uji emulator otomatis — sebelum ada proxy/CF/UI apa pun yang menyentuh data.

**Architecture:** Koleksi baru `customerChats` (+ subkoleksi `messages`, `internalNotes`) hanya boleh diakses staff (`owner`, atau `karyawan` ber-`canHandleCustomer`). Customer tak pernah punya identitas Firebase di project ini (Topologi A) → tak ada rule customer; proxy Next.js (Admin SDK) yang melewati rules. Perubahan minimal ke rules internal: `canHandleCustomer` dijadikan **immutable-by-self** di `users` (cabang CREATE **dan** UPDATE) agar karyawan tak bisa self-grant. Semua ditegakkan lewat uji `@firebase/rules-unit-testing` di Firestore/Storage emulator. (Rev 5: model akses kembali ke flag `canHandleCustomer`; `role:'admin'` dibatalkan — merusak filter payroll/absensi.)

**Tech Stack:** Firestore Security Rules (`rules_version = '2'`), Firebase Storage Rules, Firebase Local Emulator Suite, `@firebase/rules-unit-testing` v4, Firebase JS SDK v11 (modular), Node.js 22 built-in test runner (`node --test`), Firebase CLI (`firebase emulators:exec`).

## Global Constraints

- Project (test): gunakan `demo-tokochat` (prefix `demo-` = emulator offline, tanpa kredensial). Project produksi tetap `tokochat-a8879`.
- Rules diuji **hanya** lewat emulator; JANGAN `firebase deploy` di plan ini.
- JANGAN mengubah rule internal apa pun selain: (a) menambah guard `canHandleCustomer` di blok `users` (satu penambahan di CREATE, satu di UPDATE); (b) menambah blok BARU `match /customerChats/...` (Task 2); (c) menambah blok BARU `match /app_settings/...` (Task 7, owner-write/staff-read untuk kill-switch + jam operasional). Semua match block lain di `firestore.rules` harus tetap identik.
- Role hanya `owner`/`karyawan`. `canHandleCustomer` = boolean di `users/{uid}`, default dianggap `false` bila absen (`.get('canHandleCustomer', false)`). Staff yang boleh akses Customer Inbox = `owner` atau `karyawan` ber-`canHandleCustomer`.
- `chatId` = `cust_<nataloMemberId>` (string). Nilai `customerId` = id member Natalo (string), BUKAN uid Firebase.
- Firebase CLI sudah tersedia di mesin dev (repo ini sudah dipakai deploy rules/functions).
- Semua path di plan ini relatif ke root repo `NLCHAT` (`C:/Users/USER/Desktop/NLCHAT`), kecuali disebут lain.

---

## File Structure

- `NLCHAT/firestore.rules` — **modify**: tambah blok `match /customerChats/...`; tambah guard `canHandleCustomer` di blok `users` (CREATE + UPDATE).
- `NLCHAT/firestore.indexes.json` — **modify**: tambah composite index `customerChats(status, lastMessageAt)`.
- `NLCHAT/storage.rules` — **modify**: tambah blok `customer_chat_images/{chatId}/{file}`.
- `NLCHAT/firebase.json` — **modify**: tambah blok `emulators` (firestore + storage).
- `NLCHAT/firestore-tests/package.json` — **create**: harness uji (deps + script).
- `NLCHAT/firestore-tests/helpers.mjs` — **create**: util test env (setup/teardown, seed users).
- `NLCHAT/firestore-tests/smoke.test.mjs` — **create**: smoke test harness.
- `NLCHAT/firestore-tests/customerChats.test.mjs` — **create**: uji akses `customerChats` + subkoleksi.
- `NLCHAT/firestore-tests/users-escalation.test.mjs` — **create**: uji anti-eskalasi `canHandleCustomer`.
- `NLCHAT/firestore-tests/storage.test.mjs` — **create**: uji Storage `customer_chat_images`.
- `NLCHAT/firestore-tests/.gitignore` — **create**: abaikan `node_modules`.

---

### Task 1: Harness uji rules + konfigurasi emulator

**Files:**
- Create: `firestore-tests/package.json`
- Create: `firestore-tests/.gitignore`
- Create: `firestore-tests/helpers.mjs`
- Create: `firestore-tests/smoke.test.mjs`
- Modify: `firebase.json` (tambah blok `emulators`)

**Interfaces:**
- Produces: `helpers.mjs` mengekspor `getTestEnv()` → `Promise<RulesTestEnvironment>`, `seedUser(env, uid, data)` → `Promise<void>`, dan konstanta `PROJECT_ID = 'demo-tokochat'`. Task 2–5 mengimpor ini.

- [ ] **Step 1: Buat `firestore-tests/.gitignore`**

```
node_modules/
firebase-debug.log
firestore-debug.log
ui-debug.log
```

- [ ] **Step 2: Buat `firestore-tests/package.json`**

```json
{
  "name": "nlcatter-firestore-tests",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "description": "Uji Security Rules Firestore/Storage tokochat via emulator",
  "scripts": {
    "test": "firebase emulators:exec --only firestore,storage --project demo-tokochat --config ../firebase.json \"node --test\""
  },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^4.0.1",
    "firebase": "^11.3.0"
  }
}
```

- [ ] **Step 3: Tambah blok `emulators` ke `firebase.json`**

Ubah `firebase.json`: setelah blok `"functions": [...]` (dan sebelum `}` penutup terluar), tambahkan koma lalu blok berikut sehingga bagian akhir file menjadi:

```json
  "functions": [
    {
      "source": "functions",
      "codebase": "default",
      "ignore": [
        "node_modules",
        ".git",
        "*.log"
      ]
    }
  ],
  "emulators": {
    "firestore": { "port": 8080 },
    "storage": { "port": 9199 },
    "singleProjectMode": true,
    "ui": { "enabled": false }
  }
}
```

- [ ] **Step 4: Buat `firestore-tests/helpers.mjs`**

```js
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";

export const PROJECT_ID = "demo-tokochat";

const firestoreRules = readFileSync(
  fileURLToPath(new URL("../firestore.rules", import.meta.url)),
  "utf8",
);
const storageRules = readFileSync(
  fileURLToPath(new URL("../storage.rules", import.meta.url)),
  "utf8",
);

// Host/port emulator dibaca otomatis dari env var yang di-set
// `firebase emulators:exec` (FIRESTORE_EMULATOR_HOST / FIREBASE_STORAGE_EMULATOR_HOST).
export function getTestEnv() {
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: firestoreRules },
    storage: { rules: storageRules },
  });
}

// Seed dokumen users/{uid} MENGABAIKAN rules (context admin) supaya
// canCS()/isOwner() punya data untuk di-get() saat uji akses.
export async function seedUser(env, uid, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", uid), data);
  });
}

export { assertFails, assertSucceeds };
```

- [ ] **Step 5: Buat `firestore-tests/smoke.test.mjs`**

```js
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { doc, getDoc, setDoc } from "firebase/firestore";
import { getTestEnv, assertSucceeds } from "./helpers.mjs";

let env;
before(async () => { env = await getTestEnv(); });
after(async () => { await env.cleanup(); });

test("harness: owner dapat baca dokumennya sendiri (rules users existing)", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", "owner1"), { role: "owner" });
  });
  const db = env.authenticatedContext("owner1").firestore();
  await assertSucceeds(getDoc(doc(db, "users", "owner1")));
});
```

- [ ] **Step 6: Install deps**

Run (dari `firestore-tests/`): `npm install`
Expected: `node_modules/` terisi; tanpa error.

- [ ] **Step 7: Jalankan smoke test**

Run (dari `firestore-tests/`): `npm test`
Expected: emulator Firestore+Storage menyala, `node --test` melaporkan `# pass 1` / `tests 1 ... pass 1`, exit code 0.

- [ ] **Step 8: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add firestore-tests/.gitignore firestore-tests/package.json firestore-tests/package-lock.json firestore-tests/helpers.mjs firestore-tests/smoke.test.mjs firebase.json
git -C C:/Users/USER/Desktop/NLCHAT commit -m "test(rules): harness uji emulator Firestore/Storage untuk customer chat"
```

---

### Task 2: Rules `customerChats` (root) — staff-only

**Files:**
- Test: `firestore-tests/customerChats.test.mjs`
- Modify: `firestore.rules` (tambah blok `match /customerChats/{chatId}`)

**Interfaces:**
- Consumes: `getTestEnv`, `seedUser`, `assertFails`, `assertSucceeds` dari `helpers.mjs`.
- Produces: fungsi rules `canCS()` di dalam `match /customerChats/{chatId}` (dipakai Task 3 untuk subkoleksi).

- [ ] **Step 1: Tulis test yang gagal**

Buat `firestore-tests/customerChats.test.mjs`:

```js
import { test, before, after, beforeEach } from "node:test";
import { doc, getDoc, setDoc, collection, getDocs, query, where, orderBy } from "firebase/firestore";
import { getTestEnv, seedUser, assertFails, assertSucceeds } from "./helpers.mjs";

let env;
before(async () => { env = await getTestEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await seedUser(env, "owner1", { role: "owner" });
  await seedUser(env, "cs1", { role: "karyawan", canHandleCustomer: true });
  await seedUser(env, "kar1", { role: "karyawan" }); // tanpa flag
  // Seed satu room mengabaikan rules.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "customerChats", "cust_m123"), {
      customerId: "m123", status: "open", lastMessageAt: 1,
    });
  });
});

const roomRef = (db) => doc(db, "customerChats", "cust_m123");

test("owner boleh baca room customer", async () => {
  const db = env.authenticatedContext("owner1").firestore();
  await assertSucceeds(getDoc(roomRef(db)));
});

test("karyawan ber-canHandleCustomer boleh baca room customer", async () => {
  const db = env.authenticatedContext("cs1").firestore();
  await assertSucceeds(getDoc(roomRef(db)));
});

test("karyawan TANPA canHandleCustomer ditolak baca room customer", async () => {
  const db = env.authenticatedContext("kar1").firestore();
  await assertFails(getDoc(roomRef(db)));
});

test("user tak login ditolak baca room customer", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(roomRef(db)));
});

test("CS boleh create room baru; kar1 ditolak", async () => {
  const csDb = env.authenticatedContext("cs1").firestore();
  await assertSucceeds(setDoc(doc(csDb, "customerChats", "cust_m999"), {
    customerId: "m999", status: "open", lastMessageAt: 2,
  }));
  const karDb = env.authenticatedContext("kar1").firestore();
  await assertFails(setDoc(doc(karDb, "customerChats", "cust_m888"), {
    customerId: "m888", status: "open", lastMessageAt: 3,
  }));
});

test("CS boleh list customerChats; kar1 ditolak", async () => {
  const csDb = env.authenticatedContext("cs1").firestore();
  const q = query(
    collection(csDb, "customerChats"),
    where("status", "in", ["open", "waiting_customer", "waiting_staff"]),
    orderBy("lastMessageAt", "desc"),
  );
  await assertSucceeds(getDocs(q));
  const karDb = env.authenticatedContext("kar1").firestore();
  await assertFails(getDocs(query(collection(karDb, "customerChats"))));
});

test("delete room selalu ditolak (bahkan owner)", async () => {
  const { deleteDoc } = await import("firebase/firestore");
  const db = env.authenticatedContext("owner1").firestore();
  await assertFails(deleteDoc(roomRef(db)));
});
```

- [ ] **Step 2: Jalankan test untuk memastikan GAGAL**

Run (dari `firestore-tests/`): `npm test`
Expected: test `customerChats.test.mjs` gagal — akses ditolak untuk SEMUA (blok `customerChats` belum ada → default deny), sehингga test "owner boleh baca" dan "CS boleh baca" FAIL.

- [ ] **Step 3: Tambah blok `customerChats` ke `firestore.rules`**

Di `firestore.rules`, TEPAT SEBELUM blok `// stock_products:` (baris komentar `// stock_products: semua user login bisa baca.`), sisipkan:

```
    // customerChats: chat customer↔toko (Topologi A). Customer TAK punya
    // identitas Firebase di project ini → tak ada rule customer; proxy
    // Next.js (Admin SDK) melewati rules. Staff = owner atau karyawan
    // ber-canHandleCustomer. Lihat spec 2026-07-06 customer-chat §5.
    match /customerChats/{chatId} {
      function canCS() {
        return isSignedIn() && (
          isOwner()
          || get(/databases/$(database)/documents/users/$(request.auth.uid))
               .data.get('canHandleCustomer', false) == true
        );
      }
      allow read: if canCS();
      allow create: if false; // room HANYA dibuat proxy (Admin SDK, lewati rules); staff tak pernah buat room
      allow update: if canCS()
        && request.resource.data.diff(resource.data).affectedKeys()
             .hasOnly(['status', 'statusChangedBy', 'statusChangedAt',
                       'typingStaff', 'unreadCount',
                       'lastMessageText', 'lastMessageType', 'lastMessageAt', 'lastMessageSender',
                       'updatedAt']); // identitas/snapshot customer = proxy/CF-only
      allow delete: if false;

      match /messages/{messageId} {
        allow read: if canCS();
        allow create: if canCS() && request.resource.data.senderRole == 'staff'; // anti-forgery: pesan customer via proxy
        allow update: if canCS()
          && request.resource.data.diff(resource.data).affectedKeys()
               .hasOnly(['readByStaffAt', 'readByCustomerAt', 'status']); // konten immutable, hanya penanda baca
        allow delete: if false;
      }
      match /internalNotes/{noteId} {
        allow read, create: if canCS();
        allow update, delete: if false;
      }
    }

```

- [ ] **Step 4: Jalankan test untuk memastikan LULUS**

Run (dari `firestore-tests/`): `npm test`
Expected: semua test di `customerChats.test.mjs` PASS; smoke test tetap PASS.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add firestore.rules firestore-tests/customerChats.test.mjs
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(rules): customerChats root staff-only (owner|canHandleCustomer)"
```

---

### Task 3: Rules subkoleksi `messages` & `internalNotes`

**Files:**
- Test: `firestore-tests/customerChats.test.mjs` (tambah test)

**Interfaces:**
- Consumes: `canCS()` + blok subkoleksi dari Task 2 (sudah ditulis bersamaan di Step 3 Task 2; task ini menegakkannya lewat test).

- [ ] **Step 1: Tulis test subkoleksi yang gagal**

Tambahkan di akhir `firestore-tests/customerChats.test.mjs` (sebelum EOF):

```js
test("CS boleh baca & create message; kar1 & anon ditolak", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "customerChats/cust_m123/messages/msg1"), {
      senderRole: "staff", type: "text", text: "halo", createdAt: 1,
    });
  });
  const csDb = env.authenticatedContext("cs1").firestore();
  await assertSucceeds(getDoc(doc(csDb, "customerChats/cust_m123/messages/msg1")));
  await assertSucceeds(setDoc(doc(csDb, "customerChats/cust_m123/messages/msg2"), {
    senderRole: "staff", type: "text", text: "balas", createdAt: 2,
  }));

  const karDb = env.authenticatedContext("kar1").firestore();
  await assertFails(getDoc(doc(karDb, "customerChats/cust_m123/messages/msg1")));

  const anonDb = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonDb, "customerChats/cust_m123/messages/msg1")));
});

test("message tak boleh dihapus siapa pun", async () => {
  const { deleteDoc } = await import("firebase/firestore");
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "customerChats/cust_m123/messages/msgDel"), {
      senderRole: "staff", type: "text", text: "x", createdAt: 1,
    });
  });
  const csDb = env.authenticatedContext("cs1").firestore();
  await assertFails(deleteDoc(doc(csDb, "customerChats/cust_m123/messages/msgDel")));
});

test("internalNotes: CS boleh baca/create, tak boleh update/delete; kar1 ditolak", async () => {
  const { updateDoc, deleteDoc } = await import("firebase/firestore");
  const csDb = env.authenticatedContext("cs1").firestore();
  await assertSucceeds(setDoc(doc(csDb, "customerChats/cust_m123/internalNotes/n1"), {
    authorId: "cs1", authorName: "CS", text: "catatan", createdAt: 1,
  }));
  await assertSucceeds(getDoc(doc(csDb, "customerChats/cust_m123/internalNotes/n1")));
  await assertFails(updateDoc(doc(csDb, "customerChats/cust_m123/internalNotes/n1"), { text: "ubah" }));
  await assertFails(deleteDoc(doc(csDb, "customerChats/cust_m123/internalNotes/n1")));

  const karDb = env.authenticatedContext("kar1").firestore();
  await assertFails(getDoc(doc(karDb, "customerChats/cust_m123/internalNotes/n1")));
});
```

- [ ] **Step 2: Jalankan test — pastikan LULUS**

Run (dari `firestore-tests/`): `npm test`
Expected: test subkoleksi baru PASS (rules subkoleksi sudah ada dari Task 2). Bila ada yang gagal, perbaiki blok subkoleksi di `firestore.rules` agar sesuai.

- [ ] **Step 3: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add firestore-tests/customerChats.test.mjs
git -C C:/Users/USER/Desktop/NLCHAT commit -m "test(rules): tegakkan messages & internalNotes customerChats staff-only"
```

---

### Task 4: Anti-eskalasi `canHandleCustomer` di `users`

**Files:**
- Test: `firestore-tests/users-escalation.test.mjs`
- Modify: `firestore.rules` (blok `match /users/{uid}` — guard di CREATE & UPDATE)

**Interfaces:**
- Consumes: `getTestEnv`, `seedUser`, `assertFails`, `assertSucceeds`.

- [ ] **Step 1: Tulis test eskalasi yang gagal**

Buat `firestore-tests/users-escalation.test.mjs`:

```js
import { test, before, after, beforeEach } from "node:test";
import { doc, setDoc, updateDoc, deleteDoc } from "firebase/firestore";
import { getTestEnv, seedUser, assertFails, assertSucceeds } from "./helpers.mjs";

let env;
before(async () => { env = await getTestEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await seedUser(env, "owner1", { role: "owner" });
  await seedUser(env, "kar1", { role: "karyawan", canHandleCustomer: false });
});

test("karyawan TAK bisa self-set canHandleCustomer via update", async () => {
  const db = env.authenticatedContext("kar1").firestore();
  await assertFails(updateDoc(doc(db, "users", "kar1"), { canHandleCustomer: true }));
});

test("karyawan TAK bisa self-grant via delete lalu recreate dgn flag true", async () => {
  const db = env.authenticatedContext("kar1").firestore();
  await assertSucceeds(deleteDoc(doc(db, "users", "kar1"))); // delete diri sendiri: diizinkan (existing)
  await assertFails(setDoc(doc(db, "users", "kar1"), {
    role: "karyawan", canHandleCustomer: true,
  }));
});

test("karyawan boleh recreate dirinya dgn flag false/absent", async () => {
  const db = env.authenticatedContext("kar1").firestore();
  await assertSucceeds(deleteDoc(doc(db, "users", "kar1")));
  await assertSucceeds(setDoc(doc(db, "users", "kar1"), { role: "karyawan" }));
});

test("owner boleh set canHandleCustomer=true pada karyawan", async () => {
  const db = env.authenticatedContext("owner1").firestore();
  await assertSucceeds(updateDoc(doc(db, "users", "kar1"), { canHandleCustomer: true }));
});

test("karyawan tetap boleh update profil non-sensitif", async () => {
  const db = env.authenticatedContext("kar1").firestore();
  await assertSucceeds(updateDoc(doc(db, "users", "kar1"), { nama: "Budi" }));
});
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run (dari `firestore-tests/`): `npm test`
Expected: `users-escalation.test.mjs` gagal pada dua test kunci — "self-set via update" dan "self-grant via delete→recreate" saat ini LULUS menulis (assertFails gagal) karena rules belum menjaga `canHandleCustomer`.

- [ ] **Step 3: Tambah guard CREATE di blok `users`**

Di `firestore.rules`, blok `match /users/{uid}`, cabang `allow create`. Ganti:

```
      allow create: if isSignedIn() && (
        isOwner()
        || (request.auth.uid == uid
            && request.resource.data.role == 'karyawan')
      );
```

menjadi:

```
      allow create: if isSignedIn() && (
        isOwner()
        || (request.auth.uid == uid
            && request.resource.data.role == 'karyawan'
            && request.resource.data.get('canHandleCustomer', false) == false)
      );
```

- [ ] **Step 4: Tambah guard UPDATE di blok `users`**

Di cabang `allow update` blok `users`, di dalam kondisi self-update, tambahkan pengecekan `canHandleCustomer` immutable. Ganti:

```
        || (request.auth.uid == uid
            && request.resource.data.role == resource.data.role
            && request.resource.data.get('active', true)
               == resource.data.get('active', true)
            && request.resource.data.get('ikutAbsensi', true)
               == resource.data.get('ikutAbsensi', true))
```

menjadi:

```
        || (request.auth.uid == uid
            && request.resource.data.role == resource.data.role
            && request.resource.data.get('active', true)
               == resource.data.get('active', true)
            && request.resource.data.get('ikutAbsensi', true)
               == resource.data.get('ikutAbsensi', true)
            && request.resource.data.get('canHandleCustomer', false)
               == resource.data.get('canHandleCustomer', false))
```

- [ ] **Step 5: Jalankan test — pastikan LULUS**

Run (dari `firestore-tests/`): `npm test`
Expected: seluruh `users-escalation.test.mjs` PASS; test-test lain (smoke, customerChats) tetap PASS (tak ada regresi).

- [ ] **Step 6: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add firestore.rules firestore-tests/users-escalation.test.mjs
git -C C:/Users/USER/Desktop/NLCHAT commit -m "fix(rules): canHandleCustomer immutable-by-self (create + update) anti-eskalasi"
```

---

### Task 5: Composite index `customerChats`

**Files:**
- Modify: `firestore.indexes.json`
- Test: `firestore-tests/index-shape.test.mjs` (validasi bentuk JSON + kesesuaian query)

**Interfaces:**
- Consumes: —. Index mendukung query tab Customer: `where status in [...] orderBy lastMessageAt desc`.

- [ ] **Step 1: Tulis test bentuk index yang gagal**

Buat `firestore-tests/index-shape.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const idx = JSON.parse(readFileSync(
  fileURLToPath(new URL("../firestore.indexes.json", import.meta.url)), "utf8"));

test("ada composite index customerChats(status ASC, lastMessageAt DESC)", () => {
  const found = (idx.indexes || []).some((i) =>
    i.collectionGroup === "customerChats" &&
    i.queryScope === "COLLECTION" &&
    Array.isArray(i.fields) &&
    i.fields.length === 2 &&
    i.fields[0].fieldPath === "status" && i.fields[0].order === "ASCENDING" &&
    i.fields[1].fieldPath === "lastMessageAt" && i.fields[1].order === "DESCENDING"
  );
  assert.ok(found, "index customerChats(status, lastMessageAt) belum ada");
});
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run (dari `firestore-tests/`): `npm test`
Expected: `index-shape.test.mjs` FAIL ("index ... belum ada").

- [ ] **Step 3: Tambah index ke `firestore.indexes.json`**

Di array `"indexes"` pada `firestore.indexes.json`, tambahkan entri objek berikut (koma sesuai posisi) sehingga menjadi anggota array:

```json
    {
      "collectionGroup": "customerChats",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "lastMessageAt", "order": "DESCENDING" }
      ]
    }
```

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run (dari `firestore-tests/`): `npm test`
Expected: `index-shape.test.mjs` PASS; JSON valid (tak ada error parse). (Efektivitas index sebenarnya diverifikasi saat deploy/query di Plan 2/5, bukan di sini.)

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add firestore.indexes.json firestore-tests/index-shape.test.mjs
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(index): composite customerChats(status, lastMessageAt) untuk tab Customer"
```

---

### Task 6: Storage rules `customer_chat_images`

**Files:**
- Test: `firestore-tests/storage.test.mjs`
- Modify: `storage.rules` (tambah blok `customer_chat_images/{chatId}/{file}`)

**Interfaces:**
- Consumes: `getTestEnv` (sudah memuat `storage: { rules }`).
- **Catatan (Rev 5):** spec §4.3 memutuskan foto chat customer **kedua arah** (customer & staff) lewat UploadThing via proxy → blok `customer_chat_images/` ini secara desain **tidak terpakai**. Task 6 dipertahankan (permintaan user) sebagai fallback/defense-in-depth opsional yang **tak berbahaya** (rule auth-only, tak menabrak fitur lain). Bila ingin plan 1:1 dengan spec, Task 6 boleh di-skip tanpa efek.

- [ ] **Step 1: Tulis test Storage yang gagal**

Buat `firestore-tests/storage.test.mjs`:

```js
import { test, before, after } from "node:test";
import { ref, uploadString, getBytes } from "firebase/storage";
import { getTestEnv, assertFails, assertSucceeds } from "./helpers.mjs";

let env;
before(async () => { env = await getTestEnv(); });
after(async () => { await env.cleanup(); });

const path = "customer_chat_images/cust_m123/foto1.txt";

test("staff login boleh tulis & baca customer_chat_images", async () => {
  const st = env.authenticatedContext("cs1").storage();
  await assertSucceeds(uploadString(ref(st, path), "halo"));
  await assertSucceeds(getBytes(ref(st, path)));
});

test("user tak login ditolak tulis customer_chat_images", async () => {
  const st = env.unauthenticatedContext().storage();
  await assertFails(uploadString(ref(st, path), "halo"));
});
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run (dari `firestore-tests/`): `npm test`
Expected: `storage.test.mjs` gagal pada "staff boleh tulis" (path `customer_chat_images` belum ada rule → deny).

- [ ] **Step 3: Tambah blok ke `storage.rules`**

Di `storage.rules`, setelah blok `match /chat_images/{chatId}/{file} { ... }` (baris `// Foto di chat biasa`), tambahkan:

```
    // Foto chat CUSTOMER yang dikirim STAFF dari NLCATTER (native).
    // Foto dari customer disimpan di UploadThing via proxy Next.js, bukan di sini.
    match /customer_chat_images/{chatId}/{file} {
      allow read, write: if request.auth != null;
    }
```

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run (dari `firestore-tests/`): `npm test`
Expected: `storage.test.mjs` PASS; seluruh test lain tetap PASS.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add storage.rules firestore-tests/storage.test.mjs
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(storage): rule customer_chat_images (foto staff) auth-only"
```

---

### Task 7: Rules `app_settings` (owner-write, staff-read) — TDD

> Ditambah dari review konsistensi (fix B5): kill-switch `app_settings/chatConfig` & jam operasional `app_settings/chatHours` ditulis **owner dari NLCATTER** (keputusan user 2026-07-07, bukan mirror/Prisma). Proxy Natalo hanya membaca (Admin SDK, lewati rules). Baca = semua staff login (banner kill-switch di inbox).

**Files:**
- Test: `firestore-tests/app-settings.test.mjs`
- Modify: `firestore.rules` (tambah blok `match /app_settings/{docId}`)

**Interfaces:**
- Consumes: `getTestEnv`, `seedUser`, `assertFails`, `assertSucceeds` dari `helpers.mjs`.

- [ ] **Step 1: Tulis test yang gagal** (`firestore-tests/app-settings.test.mjs`): seed `owner1{role:owner}`, `kar1{role:karyawan}`. Uji: owner boleh `setDoc app_settings/chatConfig {chatEnabled:false}` (assertSucceeds) & `app_settings/chatHours` (assertSucceeds); `kar1` DITOLAK tulis (assertFails) tapi BOLEH baca (assertSucceeds); anon DITOLAK baca (assertFails).

- [ ] **Step 2: Jalankan — GAGAL** (blok belum ada → default deny untuk owner write). `npm test`.

- [ ] **Step 3: Tambah blok ke `firestore.rules`** (setelah blok `customerChats`, sebelum blok berikutnya):

```
    // app_settings: konfigurasi chat (chatConfig=kill-switch, chatHours=jam
    // operasional). Ditulis OWNER dari NLCATTER; dibaca semua staff login
    // (banner kill-switch inbox) + proxy Natalo (Admin SDK, lewati rules).
    match /app_settings/{docId} {
      allow read: if isSignedIn();
      allow write: if isOwner();
    }
```

- [ ] **Step 4: Jalankan — LULUS.** `npm test`.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add firestore.rules firestore-tests/app-settings.test.mjs
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(rules): app_settings owner-write, staff-read (kill-switch + jam operasional)"
```

---

## Definition of Done (Plan 1)

- [ ] `npm test` di `firestore-tests/` hijau penuh (smoke + customerChats + messages/internalNotes + escalation + index-shape + storage + app-settings).
- [ ] `firestore.rules`: blok `customerChats` ada (canCS berbasis `owner || canHandleCustomer`); blok `users` menjaga `canHandleCustomer` di CREATE & UPDATE; blok `app_settings` (owner-write, staff-read); blok lain tak berubah.
- [ ] `firestore.indexes.json`: index `customerChats(status, lastMessageAt)` ada.
- [ ] `storage.rules`: blok `customer_chat_images` ada.
- [ ] `firebase.json`: blok `emulators` ada.
- [ ] Tak ada `firebase deploy` yang dijalankan (deploy = tahap terpisah, sesudah review).

## Self-Review (penulis plan)

- **Cakupan spec §5 (Rev 5):** canCS() staff-only berbasis `owner || canHandleCustomer` ✓ (Task 2), internalNotes staff-only immutable ✓ (Task 3), anti-eskalasi `canHandleCustomer` guard CREATE+UPDATE ✓ (Task 4), index ✓ (Task 5), storage ✓ (Task 6). Validasi proxy & auth server-to-server = Plan 2 (di luar cakupan fondasi rules).
- **Placeholder scan:** semua step berisi kode/perintah konkret; tak ada "TODO/dst".
- **Konsistensi tipe/nama:** `canCS`, `PROJECT_ID='demo-tokochat'`, `getTestEnv`, `seedUser`, path `customerChats/cust_m123/...` konsisten lintas task.
- **Catatan verifikasi:** efektivitas index & performa query diuji di Plan 2/5 (butuh data & query nyata), bukan unit rules.
