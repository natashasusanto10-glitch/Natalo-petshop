# Customer Chat — Plan 2: Proxy Next.js (Natalo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **STATUS (2026-07-07): EXECUTED** di branch `feat/customer-chat-plan-2-proxy` (Natalo repo), 15 commit, **133/133 test hijau**, lolos review per-task + **whole-branch opus (nol blocker keamanan)**. **Belum di-deploy** (Vercel deploy = langkah gated terpisah). Semua 8 syarat keamanan terpenuhi (anti-IDOR 4 route, allowlist projection, gate order, webhook HMAC raw-body, isolasi kredensial `tokochat` vs `natalo-fcm`, proxy tak tulis unread, anti-spoof context, staging bersih). **Divergensi vs teks plan di bawah (hardening yang di-ship):**
> - `projectMessageForCustomer`: field NESTED `product`/`order` ikut di-allowlist per-field (bukan cast objek) — cegah bocor cost/margin/supplier.
> - `GET /api/chat/[chatId]`: paginasi `hasMore`/`nextCursor` berbasis **RAW doc count** (bukan array terprojeksi) — drop `staffOnly` tak lagi memotong riwayat.
> - Agregat order (ringkasan customer, Task 5): difilter `status notIn [CANCELLED,REFUNDED,PENDING]`.
> - `send-image` JUGA membangun snapshot customer (paritas `send`) — room yg pesan pertamanya foto tetap dapat nama/phone/summary.
> - Auto-reopen + auto-greeting/away diekstrak ke **`lib/chat/auto-effects.ts`**, dipakai KEDUA route `send` + `send-image`.
> - Webhook dedupe: bedakan `ALREADY_EXISTS`(6)→200 dedup vs error lain→**500** (CF retry self-heal).
> - `lib/chat/firestore-admin.ts` reuse `normalizePemKey` dari `lib/pem-utils.ts`; helper `isChatEnabled`/`getHoursStatus` ada di `app/api/chat/config/route.ts`.
> - **Catatan Plan 4 (WAJIB):** render pesan auto/system berdasarkan `type==='system'`, BUKAN `senderRole` (projeksi memetakan `system`→`customer`).
> - **Ship-as-debt (fast-follow):** `clientMsgId` sbg doc-id deterministik (idempotensi anti-race); index DB `Order(userId)`; ekstrak konstanta nama-koleksi bersama.
> - Blok kode di task-task bawah masih menampilkan versi awal; sumber kebenaran = kode yang di-ship + banner ini.

**Goal:** Membangun lapisan **proxy** di Natalo Next.js (repo ini) yang menjadi satu-satunya jalan customer mengirim/membaca chat. Customer TAK pernah punya identitas Firebase di `tokochat-a8879` (Topologi A); proxy memakai **Firebase Admin SDK** (service account tokochat, app terpisah) untuk menulis `customerChats/*` di Firestore, dengan sesi Natalo (`getSession('CUSTOMER')`) sebagai otoritas identitas. Fondasi rules sudah ditegakkan di **Plan 1** (repo NLCHAT); plan ini adalah lapisan tulis/baca server-to-server-nya.

**Architecture:**
- **Identitas:** `session.sub` (Prisma `User.id`, cuid) = pemilik room. `chatId = cust_<User.id>`. Proxy melewati Security Rules (Admin SDK), jadi keamanan ditegakkan **di proxy** (session gate + CSRF + allowlist projection + kill-switch + rate-limit), BUKAN client-side.
- **Admin SDK terpisah:** repo sudah pakai `firebase-admin` untuk FCM project `natalopetshop` (app bernama `natalo-fcm` di `lib/fcm.ts`). tokochat memakai **app kedua** bernama `tokochat` dengan kredensial sendiri — kredensial TIDAK dicampur.
- **Logika teruji = fungsi murni.** Repo menguji helper murni via `tsx --test tests/*.test.ts` (`node:test`), tanpa DB/emulator. Maka semua logika (derivasi chatId, projeksi allowlist, idempotensi, verifikasi HMAC webhook, sliding-window rate-limit, parsing kill-switch) diekstrak ke `lib/chat/*` sebagai fungsi murni yang diuji langsung; route handler tetap tipis (rakit request → panggil helper → `NextResponse.json`).
- **Kill-switch (refinement vs spec §11b — lihat Global Constraints):** sumber = dokumen Firestore `app_settings/chatConfig` di tokochat (dibaca proxy via Admin SDK, di-toggle owner dari NLCATTER). Toggle instan tanpa redeploy; **tak ada migrasi Prisma di Plan 2.**

**Tech Stack:** Next.js App Router (route handlers `app/api/chat/**`), TypeScript, `firebase-admin` v13.9 (`firebase-admin/app`, `firebase-admin/firestore`), Prisma (baca `User`/`Order`/`PushSubscription` — read-only, tanpa migrasi baru), UploadThing (`uploadToUT`), Node.js built-in test runner via `tsx` (`node:test` + `node:assert/strict`).

## Global Constraints

- **JANGAN** `firebase deploy` apa pun; proxy hanya menulis DATA lewat Admin SDK ke Firestore produksi `tokochat-a8879`. Rules/index = tanggung jawab Plan 1 (deploy terpisah, sesudah review).
- **Tanpa migrasi DB baru.** Plan 2 hanya **membaca** Prisma (`User`, `Order`, `PushSubscription`). Kill-switch & idempotensi webhook disimpan di Firestore tokochat, bukan Postgres.
- **Kill-switch (DIPUTUSKAN):** sumber = doc Firestore `app_settings/chatConfig` di tokochat (bukan tabel Prisma `AppConfig` seperti spec §11b awal). Alasan: (a) toggle instan tanpa redeploy Next.js — penting untuk "emergency off"; (b) bisa di-flip owner langsung dari NLCATTER; (c) sumber tunggal, tak ada mirror; (d) nol migrasi. Keputusan final user 2026-07-07.
- **Keamanan ditegakkan di proxy, bukan client.** Setiap handler customer: `getSession('CUSTOMER')` → 401 bila null; `assertSameOrigin` untuk mutasi (POST); cek kill-switch → 503 bila off; rate-limit; GET pakai **allowlist projection** (jangan bocorkan `internalNotes`, `staffOnly:true`, field internal room).
- **Chat customer TIDAK boleh membaca** koleksi internal tokochat apa pun (`users`, `stock_products`, payroll/absensi, `internalChats`). Proxy hanya menyentuh path `customerChats/*` dan `app_settings/chatConfig`.
- **Scope Plan 2 = permukaan CUSTOMER + webhook masuk (CF→FCM customer).** Endpoint NLCATTER-facing (`/api/catalog/search`, `/api/chat/staff-send-image` yang di-auth Firebase ID token) DITUNDA ke plan Cloud Functions/NLCATTER (butuh verifikasi ID token staff) — dicatat di §Deferred.
- Env baru dideklarasikan di `.env.example` mengikuti pola `FCM_*` (individual fields + `normalizePemKey`), BUKAN JSON blob.
- Semua path relatif ke root repo Natalo (`C:/Users/USER/Desktop/natalopetshopflutter`).

---

## File Structure

- `.env.example` — **modify**: tambah `TOKOCHAT_PROJECT_ID`, `TOKOCHAT_CLIENT_EMAIL`, `TOKOCHAT_PRIVATE_KEY`, `CHAT_WEBHOOK_SECRET`.
- `lib/chat/firestore-admin.ts` — **create**: singleton Admin SDK app `tokochat` + `getTokochatFirestore()`; reuse `normalizePemKey`.
- `lib/chat/core.ts` — **create**: fungsi murni — `chatIdForUser`, `projectMessageForCustomer`, `isValidClientMsgId`, `verifyWebhookSignature`, `slidingWindowAllow`, `parseChatEnabled`.
- `lib/chat/rooms.ts` — **create**: penulisan room/message (dependency-injected Firestore + Prisma repo agar bisa diuji), `buildCustomerSnapshot`, `writeCustomerMessage`, `upsertRoom`.
- `app/api/chat/config/route.ts` — **create**: `GET` kill-switch `{ chatEnabled }`.
- `app/api/chat/send/route.ts` — **create**: `POST` kirim teks (idempoten, auto-greeting hook).
- `app/api/chat/send-image/route.ts` — **create**: `POST` kirim foto via UploadThing.
- `app/api/chat/[chatId]/route.ts` — **create**: `GET` daftar pesan (projeksi allowlist) + tandai baca.
- `app/api/chat/unread/route.ts` — **create**: `GET` `{ unreadForCustomer }` untuk badge.
- `app/api/chat/webhook/route.ts` — **create**: `POST` terima pesan staff dari CF tokochat (HMAC) → `sendFcmToUser`.
- `tests/chat-core.test.ts` — **create**: uji fungsi murni `lib/chat/core.ts`.
- `tests/chat-rooms.test.ts` — **create**: uji `buildCustomerSnapshot`/`writeCustomerMessage` dgn fake DI.
- `tests/chat-webhook.test.ts` — **create**: uji verifikasi HMAC + idempotensi.

---

### Task 1: Admin SDK tokochat (app terpisah) + env

**Files:**
- Modify: `.env.example`
- Create: `lib/chat/firestore-admin.ts`

**Interfaces:**
- Produces: `getTokochatFirestore(): Firestore` (singleton, lazy) — dipakai `lib/chat/rooms.ts`, config route, webhook route.
- Consumes: pola init & `normalizePemKey` dari `lib/fcm.ts` (jangan diimpор lintas-modul bila `normalizePemKey` tak diekspор; duplikasi kecil helper PEM diizinkan, atau ekspор dari `lib/fcm.ts`).

- [ ] **Step 1: Tambah env ke `.env.example`**

Setelah blok `FCM_*`, tambahkan:

```bash
# ---- Customer Chat (project tokochat-a8879) ----
# Service account TERPISAH dari FCM natalopetshop. Jangan campur kredensial.
TOKOCHAT_PROJECT_ID=""
TOKOCHAT_CLIENT_EMAIL=""
TOKOCHAT_PRIVATE_KEY=""
# Shared secret HMAC untuk webhook Cloud Function tokochat -> proxy Natalo.
CHAT_WEBHOOK_SECRET=""
```

- [ ] **Step 2: Buat `lib/chat/firestore-admin.ts`**

```ts
import { cert, getApp, getApps, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

const APP_NAME = "tokochat";

// tokochat memakai PEM yang bisa datang dgn "\n" ter-escape (env single-line).
function normalizePemKey(raw: string): string {
  return raw.includes("\\n") ? raw.replace(/\\n/g, "\n") : raw;
}

function getTokochatApp(): App {
  const existing = getApps().find((a) => a.name === APP_NAME);
  if (existing) return getApp(APP_NAME);

  const projectId = process.env.TOKOCHAT_PROJECT_ID;
  const clientEmail = process.env.TOKOCHAT_CLIENT_EMAIL;
  const privateKey = process.env.TOKOCHAT_PRIVATE_KEY;
  if (!projectId || !clientEmail || !privateKey) {
    throw new Error("Kredensial tokochat (TOKOCHAT_*) belum di-set.");
  }
  return initializeApp(
    { credential: cert({ projectId, clientEmail, privateKey: normalizePemKey(privateKey) }) },
    APP_NAME,
  );
}

let cached: Firestore | null = null;
export function getTokochatFirestore(): Firestore {
  if (cached) return cached;
  cached = getFirestore(getTokochatApp());
  return cached;
}
```

- [ ] **Step 3: Verifikasi kompilasi (tanpa memanggil produksi)**

Run: `npx tsc --noEmit -p tsconfig.json` (atau `npm run lint`)
Expected: tak ada error tipe di `lib/chat/firestore-admin.ts`. Tidak ada pemanggilan runtime ke Firestore pada langkah ini (init lazy).

- [ ] **Step 4: Commit**

```bash
git add .env.example lib/chat/firestore-admin.ts
git commit -m "feat(chat): Admin SDK app tokochat terpisah + env service account"
```

---

### Task 2: Fungsi murni inti (`lib/chat/core.ts`) — TDD

**Files:**
- Test: `tests/chat-core.test.ts`
- Create: `lib/chat/core.ts`

**Interfaces:**
- Produces (semua murni, tanpa I/O):
  - `chatIdForUser(userId: string): string` → `cust_<userId>`.
  - `projectMessageForCustomer(raw): CustomerMessage | null` → buang `staffOnly:true`; hanya emit field yang boleh dilihat customer.
  - `isValidClientMsgId(v: unknown): v is string` → UUID/ULID sederhana, panjang wajar.
  - `verifyWebhookSignature(rawBody: string, header: string, secret: string): boolean` → HMAC-SHA256 timing-safe.
  - `slidingWindowAllow(timestampsMs: number[], nowMs: number, limit: number, windowMs: number): boolean`.
  - `parseChatEnabled(doc: unknown): boolean` → default **true** bila field absen (fail-open ke ON kecuali eksplisit `false`).

- [ ] **Step 1: Tulis test yang gagal — `tests/chat-core.test.ts`**

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { createHmac } from "node:crypto";
import {
  chatIdForUser,
  projectMessageForCustomer,
  isValidClientMsgId,
  verifyWebhookSignature,
  slidingWindowAllow,
  parseChatEnabled,
  computeChatHoursStatus,
} from "@/lib/chat/core";

test("chatIdForUser memprefix cust_", () => {
  assert.equal(chatIdForUser("ckuser123"), "cust_ckuser123");
});

test("projeksi membuang staffOnly & internal", () => {
  const staffOnly = projectMessageForCustomer({
    type: "system", text: "assigned ke CS", staffOnly: true, createdAt: 1,
  });
  assert.equal(staffOnly, null);

  const ok = projectMessageForCustomer({
    id: "m1", senderRole: "staff", senderName: "Sisca", type: "text",
    text: "halo", createdAt: 2, status: "sent",
    // field yang TAK boleh bocor:
    readByStaffAt: 99, internalFlag: true,
  } as Record<string, unknown>);
  assert.equal(ok?.text, "halo");
  assert.equal(ok?.senderRole, "staff");
  assert.equal((ok as Record<string, unknown>).readByStaffAt, undefined);
  assert.equal((ok as Record<string, unknown>).internalFlag, undefined);
});

test("isValidClientMsgId menolak sampah", () => {
  assert.equal(isValidClientMsgId("550e8400-e29b-41d4-a716-446655440000"), true);
  assert.equal(isValidClientMsgId(""), false);
  assert.equal(isValidClientMsgId("x".repeat(200)), false);
  assert.equal(isValidClientMsgId(123 as unknown), false);
});

test("verifyWebhookSignature HMAC cocok & timing-safe", () => {
  const body = JSON.stringify({ chatId: "cust_a", messageId: "m1" });
  const secret = "s3cr3t";
  const sig = createHmac("sha256", secret).update(body).digest("hex");
  assert.equal(verifyWebhookSignature(body, sig, secret), true);
  assert.equal(verifyWebhookSignature(body, "deadbeef", secret), false);
  assert.equal(verifyWebhookSignature(body, "", secret), false);
});

test("slidingWindowAllow menahan burst", () => {
  const now = 10_000;
  // 5 pesan dalam 10 dtk terakhir, limit 5 -> tolak yg ke-6
  const ts = [9500, 9000, 8500, 8000, 7500];
  assert.equal(slidingWindowAllow(ts, now, 5, 10_000), false);
  // yg lama keluar window -> izinkan
  assert.equal(slidingWindowAllow([500, 400], now, 5, 10_000), true);
});

test("parseChatEnabled default true, hanya false eksplisit yang mematikan", () => {
  assert.equal(parseChatEnabled(undefined), true);
  assert.equal(parseChatEnabled({}), true);
  assert.equal(parseChatEnabled({ chatEnabled: false }), false);
  assert.equal(parseChatEnabled({ chatEnabled: true }), true);
});

test("computeChatHoursStatus: online/di-luar-jam berbasis WIB", () => {
  const hours = { timezone: "Asia/Jakarta", days: {
    mon: { open: "08:00", close: "21:00" }, sun: { open: null, close: null } } };
  // 2024-01-01 = Senin. 05:00 UTC = 12:00 WIB -> online
  assert.equal(computeChatHoursStatus(hours, Date.UTC(2024, 0, 1, 5, 0)).online, true);
  // 15:00 UTC = 22:00 WIB -> tutup
  assert.equal(computeChatHoursStatus(hours, Date.UTC(2024, 0, 1, 15, 0)).online, false);
  // 2024-01-07 = Minggu (tutup seharian)
  assert.equal(computeChatHoursStatus(hours, Date.UTC(2024, 0, 7, 5, 0)).online, false);
});
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `npm test`
Expected: `chat-core.test.ts` gagal impor (`@/lib/chat/core` belum ada).

- [ ] **Step 3: Implementasi `lib/chat/core.ts`**

```ts
import { createHmac, timingSafeEqual } from "node:crypto";

export function chatIdForUser(userId: string): string {
  return `cust_${userId}`;
}

// Tipe pesan yang aman untuk customer. Field internal SENGAJA tak ikut.
export type CustomerMessage = {
  id?: string;
  clientMsgId?: string;
  senderRole: "customer" | "staff";
  senderName?: string;
  type: "text" | "image" | "product" | "product_context" | "order_context" | "system";
  text?: string;
  image?: { url: string };
  product?: { productId: string; slug?: string; name: string; imageUrl?: string; price?: number; stock?: number };
  order?: { orderNumber: string; status?: string; total?: number };
  auto?: boolean;
  createdAt: number;
  status?: string;
  readByCustomerAt?: number;
};

const ALLOWED_TYPES = new Set([
  "text", "image", "product", "product_context", "order_context", "system",
]);

export function projectMessageForCustomer(raw: unknown): CustomerMessage | null {
  if (!raw || typeof raw !== "object") return null;
  const m = raw as Record<string, unknown>;
  if (m.staffOnly === true) return null;
  const type = m.type;
  if (typeof type !== "string" || !ALLOWED_TYPES.has(type)) return null;

  const out: CustomerMessage = {
    senderRole: m.senderRole === "staff" ? "staff" : "customer",
    type: type as CustomerMessage["type"],
    createdAt: typeof m.createdAt === "number" ? m.createdAt : 0,
  };
  if (typeof m.id === "string") out.id = m.id;
  if (typeof m.clientMsgId === "string") out.clientMsgId = m.clientMsgId;
  if (typeof m.senderName === "string") out.senderName = m.senderName;
  if (typeof m.text === "string") out.text = m.text;
  if (m.image && typeof (m.image as Record<string, unknown>).url === "string") {
    out.image = { url: (m.image as { url: string }).url };
  }
  if (m.product && typeof m.product === "object") out.product = m.product as CustomerMessage["product"];
  if (m.order && typeof m.order === "object") out.order = m.order as CustomerMessage["order"];
  if (m.auto === true) out.auto = true;
  if (typeof m.status === "string") out.status = m.status;
  if (typeof m.readByCustomerAt === "number") out.readByCustomerAt = m.readByCustomerAt;
  return out;
}

export function isValidClientMsgId(v: unknown): v is string {
  return typeof v === "string" && v.length >= 8 && v.length <= 64 && /^[A-Za-z0-9_-]+$/.test(v);
}

export function verifyWebhookSignature(rawBody: string, header: string, secret: string): boolean {
  if (!header || !secret) return false;
  const expected = createHmac("sha256", secret).update(rawBody).digest("hex");
  const a = Buffer.from(expected, "hex");
  let b: Buffer;
  try { b = Buffer.from(header, "hex"); } catch { return false; }
  if (a.length !== b.length || a.length === 0) return false;
  return timingSafeEqual(a, b);
}

export function slidingWindowAllow(
  timestampsMs: number[], nowMs: number, limit: number, windowMs: number,
): boolean {
  const cutoff = nowMs - windowMs;
  const recent = timestampsMs.filter((t) => t > cutoff);
  return recent.length < limit;
}

export function parseChatEnabled(doc: unknown): boolean {
  if (!doc || typeof doc !== "object") return true;
  return (doc as Record<string, unknown>).chatEnabled !== false;
}

// Status jam operasional (WIB, UTC+7 tanpa DST) dari doc app_settings/chatHours.
// Dipakai: (a) GET /api/chat/config → status "Online / Di luar jam" (fix B3);
// (b) POST /api/chat/send → pilih auto-greeting vs auto-away (Task 5).
const WIB_OFFSET_MS = 7 * 60 * 60 * 1000;
const DOW = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
export function computeChatHoursStatus(
  hoursDoc: unknown, nowUtcMs: number,
): { online: boolean; timezone: string; todayOpen: string | null; todayClose: string | null } {
  const doc = (hoursDoc && typeof hoursDoc === "object" ? hoursDoc : {}) as Record<string, any>;
  const timezone = typeof doc.timezone === "string" ? doc.timezone : "Asia/Jakarta";
  const wib = new Date(nowUtcMs + WIB_OFFSET_MS);
  const today = (doc.days && doc.days[DOW[wib.getUTCDay()]]) || {};
  const open = typeof today.open === "string" ? today.open : null;
  const close = typeof today.close === "string" ? today.close : null;
  if (!open || !close) return { online: false, timezone, todayOpen: open, todayClose: close };
  const nowHhmm = `${String(wib.getUTCHours()).padStart(2, "0")}:${String(wib.getUTCMinutes()).padStart(2, "0")}`;
  return { online: nowHhmm >= open && nowHhmm < close, timezone, todayOpen: open, todayClose: close };
}
```

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `npm test`
Expected: `chat-core.test.ts` PASS; test lain tak berubah.

- [ ] **Step 5: Commit**

```bash
git add lib/chat/core.ts tests/chat-core.test.ts
git commit -m "feat(chat): helper murni core (chatId, projeksi, HMAC, rate-limit, kill-switch)"
```

---

### Task 3: Kill-switch `GET /api/chat/config` (sumber Firestore tokochat)

> **Keputusan final (2026-07-07):** sumber kill-switch = doc Firestore `app_settings/chatConfig` di tokochat. Alternatif tabel Prisma `AppConfig` ditolak (butuh migrasi + redeploy untuk toggle). Lihat Global Constraints.

**Files:**
- Create: `app/api/chat/config/route.ts`

**Interfaces:**
- Consumes: `getTokochatFirestore` (Task 1), `parseChatEnabled` (Task 2).
- Produces: helper `isChatEnabled(): Promise<boolean>` (diekspor untuk dipakai handler lain di Task 5–7).

- [ ] **Step 1: Buat `app/api/chat/config/route.ts`**

```ts
import { NextResponse } from "next/server";
import { getTokochatFirestore } from "@/lib/chat/firestore-admin";
import { parseChatEnabled, computeChatHoursStatus } from "@/lib/chat/core";

export const dynamic = "force-dynamic";

export async function isChatEnabled(): Promise<boolean> {
  try {
    const snap = await getTokochatFirestore().doc("app_settings/chatConfig").get();
    return parseChatEnabled(snap.exists ? snap.data() : undefined);
  } catch {
    // Fail-open: jika config tak terbaca, jangan matikan chat karena error infra.
    return true;
  }
}

// fix B3: status "Online / Di luar jam operasional" untuk header chat customer,
// dihitung server-side dari app_settings/chatHours (WIB) — Plan 4 tinggal render.
export async function getHoursStatus() {
  try {
    const snap = await getTokochatFirestore().doc("app_settings/chatHours").get();
    return computeChatHoursStatus(snap.exists ? snap.data() : undefined, Date.now());
  } catch {
    return { online: true, timezone: "Asia/Jakarta", todayOpen: null, todayClose: null };
  }
}

export async function GET() {
  const [chatEnabled, hours] = await Promise.all([isChatEnabled(), getHoursStatus()]);
  return NextResponse.json({ chatEnabled, online: hours.online, hours });
}
```

- [ ] **Step 2: Verifikasi tipe & lint**

Run: `npm run lint`
Expected: tak ada error. (Uji runtime kill-switch end-to-end dilakukan saat integrasi manual dgn kredensв tokochat; logika parsing sudah diuji murni di Task 2.)

- [ ] **Step 3: Commit**

```bash
git add app/api/chat/config/route.ts
git commit -m "feat(chat): GET /api/chat/config kill-switch dari app_settings/chatConfig"
```

---

### Task 4: Penulisan room & pesan (`lib/chat/rooms.ts`) — TDD dgn DI

**Files:**
- Test: `tests/chat-rooms.test.ts`
- Create: `lib/chat/rooms.ts`

**Interfaces:**
- Produces:
  - `buildCustomerSnapshot(user, orderAgg): { customerName, customerPhone, summary, summaryUpdatedAt }` — **murni**, dari data Prisma (diinject), tanpa query.
  - `writeCustomerMessage(deps, input): Promise<{ messageId, deduped: boolean }>` — idempoten via `clientMsgId`; `deps` = `{ firestore, now }` sehingga bisa difake di test.
- Consumes: `chatIdForUser` (Task 2). Query Prisma nyata dilakukan di route (Task 5), BUKAN di helper — helper menerima data siap pakai agar teruji murni.

- [ ] **Step 1: Tulis test yang gagal — `tests/chat-rooms.test.ts`**

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { buildCustomerSnapshot, writeCustomerMessage } from "@/lib/chat/rooms";

test("buildCustomerSnapshot merangkum user + agregat order", () => {
  const snap = buildCustomerSnapshot(
    { name: "Andi", phone: "0812" },
    { totalBelanja: 500000, orderCount: 3, lastOrder: { inv: "INV-9", status: "PAID", total: 150000 } },
  );
  assert.equal(snap.customerName, "Andi");
  assert.equal(snap.customerPhone, "0812");
  assert.equal(snap.summary.totalBelanja, 500000);
  assert.equal(snap.summary.lastOrder.inv, "INV-9");
  assert.equal(typeof snap.summaryUpdatedAt, "number");
});

test("writeCustomerMessage idempoten via clientMsgId", async () => {
  // Fake Firestore minimal: simpan doc by path, dukung where clientMsgId.
  const store = new Map<string, Record<string, unknown>>();
  const fakeFirestore = makeFakeFirestore(store);
  const deps = { firestore: fakeFirestore, now: () => 1000 };
  const input = {
    chatId: "cust_u1", customerId: "u1", senderRole: "customer" as const, senderId: "u1",
    senderName: "Andi", type: "text" as const, text: "halo", clientMsgId: "abcd1234",
  };
  // room hasil merge harus punya customerId (fix B2)
  // (assert bentuk room di fake store bila diinginkan)
  const first = await writeCustomerMessage(deps, input);
  const second = await writeCustomerMessage(deps, input); // retry sama
  assert.equal(second.deduped, true);
  assert.equal(first.messageId, second.messageId); // tak buat pesan dobel
});

// helper fake didefinisikan di bawah test (lihat Step 3 untuk kontrak minimal
// yang harus dipenuhi writeCustomerMessage: collection().where().get(),
// doc().set(), FieldValue increment/serverTimestamp yang di-stub angka).
```

> Catatan implementasi test: `makeFakeFirestore` cukup mengimplement subset API Admin SDK yang dipakai `writeCustomerMessage` (`collection`, `doc`, `where`, `get`, `set`, `runTransaction`). Definisikan inline di file test. Tujuan: mengunci **kontrak idempotensi & bentuk dokumen**, bukan menguji Firestore asli.

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `npm test`
Expected: `chat-rooms.test.ts` gagal impor.

- [ ] **Step 3: Implementasi `lib/chat/rooms.ts`**

Implementasikan `buildCustomerSnapshot` (murni) dan `writeCustomerMessage`:
- `writeCustomerMessage` menerima `deps.firestore` (bertipe `Firestore` Admin SDK di produksi, fake di test), melakukan: (a) cek `messages where clientMsgId == input.clientMsgId` → bila ada, kembalikan `{ messageId, deduped: true }`; (b) transaksi: `set(merge:true)` doc room dgn `createdAt` hanya bila absen, **`customerId` = `input.customerId`** (fix B2 — CF/inbox mengandalkan field ini; jangan hanya derive dari chatId), snapshot customer (`customerName/customerPhone/summary/summaryUpdatedAt`), update `lastMessage*` + `updatedAt`; (c) tulis doc pesan baru. Gunakan `FieldValue.serverTimestamp()` di produksi; di test, `deps.now()` menggantikan timestamp. `input` menyertakan `customerId` (= id customer Natalo).
- **Unread BUKAN tanggung jawab proxy** (reconciliation dgn Plan 3): counter `unreadCount.{staffUid}` & `unreadForCustomer` di-increment oleh Cloud Function `notifyNewCustomerMessage` (CF punya akses daftar `users` tokochat; proxy tidak). Proxy hanya **mereset** `unreadForCustomer=0` saat customer buka room (Task 7). Jadi `writeCustomerMessage` TIDAK menyentuh field unread.
- Bentuk dokumen pesan mengikuti spec §4.2 (field: `clientMsgId, senderRole, senderId, senderName, type, text, image?, product?, order?, auto?, staffOnly?, createdAt, status`).

(Kode lengkap ditulis saat eksekusi mengikuti kontrak test Step 1; pertahankan handler tipis — semua percabangan idempotensi ada di sini, teruji.)

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `npm test`
Expected: `chat-rooms.test.ts` PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/chat/rooms.ts tests/chat-rooms.test.ts
git commit -m "feat(chat): tulis room+pesan idempoten (clientMsgId) + snapshot customer"
```

---

### Task 5: `POST /api/chat/send` (teks)

**Files:**
- Create: `app/api/chat/send/route.ts`

**Interfaces:**
- Consumes: `getSession('CUSTOMER')`, `assertSameOrigin`, `prisma`, `isChatEnabled` (Task 3), `chatIdForUser`+`isValidClientMsgId`+`slidingWindowAllow` (Task 2), `buildCustomerSnapshot`+`writeCustomerMessage` (Task 4), `getTokochatFirestore` (Task 1).

- [ ] **Step 1: Buat handler** mengikuti pola `app/api/feed/upload-photo/route.ts` & `app/api/cart/route.ts`:

Urutan gate (WAJIB, urut):
1. `const csrf = assertSameOrigin(request); if (csrf) return csrf;`
2. `const session = await getSession("CUSTOMER"); if (!session) return 401;`
3. `if (!(await isChatEnabled())) return 503 { error: "Chat sedang nonaktif." };`
4. Parse body (`{ text, clientMsgId, context? }`) via try/catch → 400. Validasi `text` non-kosong ≤ 4000 char; `isValidClientMsgId(clientMsgId)` → 400.
5. Rate-limit: `slidingWindowAllow(recentTimestamps, Date.now(), 20, 60_000)` (sumber timestamps: query N pesan customer terakhir di room via Firestore; fail-open bila query error) → 429 bila ditolak.
6. Ambil snapshot: `prisma.user.findUnique({ where: { id: session.sub }, select: { name, phone } })` + agregat order ringan (`_sum.total`, `_count`, lastOrder). `buildCustomerSnapshot(...)`.
7. Baca doc room dulu (`roomRef.get()`) → ambil `status` & `greetingSentAt` (dipakai step 9 & 10).
8. `writeCustomerMessage({ firestore: getTokochatFirestore(), now: Date.now }, { chatId: chatIdForUser(session.sub), customerId: session.sub, senderRole: "customer", senderId: session.sub, ... })`.
9. **Auto-reopen (fix B1 / spec §8):** bila room lama `status === "resolved"`, dalam transaksi set `status = "waiting_staff"` + tulis pesan `type:"system"` (`auto:true`) teks "Percakapan dibuka kembali." agar staff tahu ada balasan baru. (Tanpa langkah ini room tetap `resolved` & staff tak sadar — gap yang ditemukan review.)
10. **Auto-greeting / away (fix B7 — PROXY-owned, bukan CF):** hanya bila room BARU (`greetingSentAt` belum ada). `computeChatHoursStatus(chatHours, Date.now())`: dalam jam → tulis pesan greeting; di luar jam → tulis pesan away (template `awayMessage` dari `chatHours`, isi `{jamBuka}/{jamTutup}`). `auto:true`, saling eksklusif, **set `greetingSentAt` atomik di transaksi yang sama** (cegah greeting dobel saat retry).
11. Return `NextResponse.json({ ok: true, messageId, deduped })`.

**Analitik (fix B8):** emit log terstruktur proxy `console.log(JSON.stringify({ event, chatId, ... }))` untuk `customer_chat_created` (room baru), `auto_greeting_sent`, `auto_away_reply_sent` → Vercel/Cloud Logging (spec §11 sisi proxy).

- [ ] **Step 2: Lint + type-check**

Run: `npm run lint`
Expected: bersih. (Verifikasi fungsional end-to-end saat integrasi dgn kredensial tokochat.)

- [ ] **Step 3: Commit**

```bash
git add app/api/chat/send/route.ts
git commit -m "feat(chat): POST /api/chat/send (session+CSRF+kill-switch+rate-limit+idempoten)"
```

---

### Task 6: `POST /api/chat/send-image`

**Files:**
- Create: `app/api/chat/send-image/route.ts`

**Interfaces:**
- Consumes: pola multipart `app/api/feed/upload-photo/route.ts` — `assertSameOrigin`, `getSession('CUSTOMER')`, `formData()`, `validateImageMagicBytes`, `uploadToUT`, lalu `writeCustomerMessage` `type: "image"`.

- [ ] **Step 1: Buat handler**
- Gate identik Task 5 (CSRF → session → kill-switch).
- `formData().get("file")`; validasi MIME allowlist (`image/jpeg|png|webp`), ukuran (mis. ≤ 5 MB → 413), `validateImageMagicBytes(buffer, file.type)` → 415.
- `const { url } = await uploadToUT(file, `chat-${session.sub}`);`
- `writeCustomerMessage(..., { type: "image", image: { url }, clientMsgId })`.
- Return `{ ok: true, url, messageId }`.

- [ ] **Step 2: Lint** → `npm run lint` bersih.

- [ ] **Step 3: Commit**

```bash
git add app/api/chat/send-image/route.ts
git commit -m "feat(chat): POST /api/chat/send-image via UploadThing + magic-byte guard"
```

---

### Task 7: `GET /api/chat/[chatId]` + `GET /api/chat/unread`

**Files:**
- Create: `app/api/chat/[chatId]/route.ts`
- Create: `app/api/chat/unread/route.ts`

**Interfaces:**
- Consumes: `getSession('CUSTOMER')`, `chatIdForUser`, `projectMessageForCustomer` (Task 2), `getTokochatFirestore`.
- **Keamanan kritis:** handler WAJIB mengabaikan `chatId` dari URL untuk otorisasi — room yang dibaca **selalu** `chatIdForUser(session.sub)`. Param `[chatId]` hanya boleh dipakai untuk validasi kecocokan (tolak 403 bila `params.chatId !== chatIdForUser(session.sub)`), TIDAK untuk memilih room. Ini mencegah customer membaca room orang lain.

- [ ] **Step 1: Buat `[chatId]/route.ts` GET**
- `session` → 401; hitung `myChat = chatIdForUser(session.sub)`; bila `params.chatId !== myChat` → 403.
- Query `customerChats/{myChat}/messages orderBy createdAt asc`, `limit(N=50)`, cursor `?after=<createdAt terakhir>` (paginasi spec §12: 30–50/halaman). Map tiap doc lewat `projectMessageForCustomer`, buang `null`.
- Tandai baca (fix C2): set room `unreadForCustomer = 0` (batch/transaksi, best-effort). **Tidak** memutasi `readByCustomerAt` per-pesan — tak diminta spec §4.2 maupun reconciliation Plan 3; disederhanakan.
- Return `{ chatId: myChat, messages, nextCursor }` — `nextCursor` = `createdAt` pesan terakhir bila `messages.length === N`, else `null` (Plan 4 pakai untuk load-more).

- [ ] **Step 2: Buat `unread/route.ts` GET**
- `session` → 401; baca doc room `chatIdForUser(session.sub)`; return `{ unreadForCustomer: number }` (0 bila room belum ada).

- [ ] **Step 3: Lint** → bersih.

- [ ] **Step 4: Commit**

```bash
git add "app/api/chat/[chatId]/route.ts" app/api/chat/unread/route.ts
git commit -m "feat(chat): GET pesan (projeksi allowlist, room terkunci ke sesi) + unread badge"
```

---

### Task 8: `POST /api/chat/webhook` (CF tokochat → FCM customer) — TDD

**Files:**
- Test: `tests/chat-webhook.test.ts`
- Create: `app/api/chat/webhook/route.ts`

**Interfaces:**
- Consumes: `verifyWebhookSignature` (Task 2), `sendFcmToUser` (`lib/fcm.ts`), `getTokochatFirestore` (idempotensi).
- **Alur:** CF di tokochat (Plan berikutnya) memanggil endpoint ini saat STAFF mengirim pesan → proxy verifikasi HMAC → dedupe `messageId` → `sendFcmToUser(customerUserId, payload)` supaya notifikasi muncul di app Natalo.

- [ ] **Step 1: Tulis test verifikasi+idempotensi** (`tests/chat-webhook.test.ts`)
- Uji fungsi ekstrak `parseWebhookPayload(raw)` (murni) + reuse `verifyWebhookSignature` (sudah diuji Task 2). Uji: payload valid → objek; body tampered → signature gagal; `messageId` yang sama → penanda dedupe.
- (Pengiriman FCM & tulis Firestore di-mock/di-DI seperti Task 4.)

- [ ] **Step 2: Jalankan — GAGAL** → `npm test`.

- [ ] **Step 3: Buat `webhook/route.ts` POST**
- Baca **raw body** (`await request.text()`), ambil header `x-chat-signature`, `verifyWebhookSignature(raw, sig, process.env.CHAT_WEBHOOK_SECRET!)` → 401 bila gagal. **Jangan** pakai session/CSRF (ini server-to-server).
- Parse JSON `{ chatId, messageId, customerUserId, preview, senderName }`.
- Idempotensi: `set` doc `customerChats/{chatId}/webhookSeen/{messageId}` dgn `create` (atau transaksi cek-lalu-tulis); bila sudah ada → 200 `{ deduped: true }` tanpa kirim FCM lagi.
- `sendFcmToUser(customerUserId, { title: senderName ?? "Natalo", body: preview, url: "/chat", tag: `chat-${chatId}`, data: { type: "customer_chat", chatId } })`.
- Return `{ ok: true }`.

- [ ] **Step 4: Jalankan — LULUS** → `npm test`.

- [ ] **Step 5: Commit**

```bash
git add app/api/chat/webhook/route.ts tests/chat-webhook.test.ts
git commit -m "feat(chat): webhook staff->customer (HMAC + idempoten) kirim FCM Natalo"
```

---

## Deferred (bukan Plan 2)

- `GET /api/catalog/search` & `POST /api/chat/staff-send-image` — **auth Firebase ID token staff**, dipakai NLCATTER. Butuh verifikasi ID token via Admin SDK tokochat (`verifyIdToken`) + cek `canHandleCustomer`. **Direncanakan penuh di Plan 2.5** (`2026-07-07-customer-chat-plan-2.5-proxy-staff-endpoints.md`).
- Cloud Function pemicu webhook & penulisan `unreadCount` per-staff (Plan 3). **Auto-greeting/away kini PROXY-owned di Task 5** (bukan ditunda). Editor jam operasional & kill-switch toggle = Plan 6 (owner NLCATTER menulis `app_settings/*`).
- Deploy rules/index tokochat (Plan 1) & konfigurasi service account produksi — tahap rilis terpisah.

## Definition of Done (Plan 2)

- [ ] `npm test` hijau: `chat-core`, `chat-rooms`, `chat-webhook` (+ 21 test existing tetap hijau, tanpa regresi).
- [ ] `lib/chat/firestore-admin.ts`: app `tokochat` terpisah dari `natalo-fcm`; init lazy; kredensial dari `TOKOCHAT_*`.
- [ ] Semua handler `/api/chat/*` customer: gate CSRF+session+kill-switch+rate-limit; GET pakai `projectMessageForCustomer`; room terkunci ke `chatIdForUser(session.sub)` (tak bisa baca room lain).
- [ ] Webhook: verifikasi HMAC timing-safe + idempotensi `messageId`; tanpa session/CSRF.
- [ ] Room menyimpan `customerId` (fix B2); auto-reopen room `resolved` saat customer kirim (fix B1); auto-greeting/away sekali per room dgn `greetingSentAt` atomik (fix B7).
- [ ] `GET /api/chat/config` mengembalikan `{chatEnabled, online, hours}` (fix B3); `GET /api/chat/[chatId]` mengembalikan `nextCursor` untuk paginasi (spec §12).
- [ ] Tak ada migrasi Prisma baru; tak ada `firebase deploy`.
- [ ] `.env.example` mendokumentasikan `TOKOCHAT_*` + `CHAT_WEBHOOK_SECRET`.

> **Prasyarat eksekusi (fix ordering):** Plan 2.5 (`catalog/search` + `staff-send-image`) adalah endpoint terpisah yang WAJIB selesai sebelum Plan 5 Task 4 (Bagikan Produk + foto staff) berfungsi. Menyelesaikan Plan 2 saja TIDAK cukup untuk Plan 5 Task 4.

## Self-Review (penulis plan)

- **Grounding kode nyata:** pola handler (`assertSameOrigin`→`getSession`→body→`NextResponse.json`) mengikuti `app/api/feed/upload-photo/route.ts` & `app/api/cart/route.ts`; helper reuse `uploadToUT`/`validateImageMagicBytes`/`sendFcmToUser`/`prisma` yang terkonfirmasi ada; test mengikuti gaya `tests/*.test.ts` (`node:test`, helper murni). ✓
- **Keamanan (constraint brief):** enforcement server-side (bukan client); room terkunci ke sesi (anti-IDOR); allowlist projection (no `internalNotes`/`staffOnly`); webhook HMAC; kill-switch. Tak menyentuh koleksi internal tokochat. ✓
- **Isolasi kredensial:** app Admin SDK kedua bernama `tokochat`, tak mencampur dgn `natalo-fcm`. ✓
- **Keputusan terkunci:** kill-switch = Firestore doc `app_settings/chatConfig` (Task 3), disetujui user 2026-07-07; alternatif tabel `AppConfig` ditolak.
- **Batas uji:** logika murni teruji penuh; efek I/O Firestore/FCM nyata diverifikasi saat integrasi manual dgn kredensial (di luar unit test, sesuai gaya repo yang tak nge-spin DB/emulator).
- **Placeholder:** Task 4 & 8 menyebut "kode lengkap ditulis saat eksekusi mengikuti kontrak test" — sengaja, karena bentuk final `writeCustomerMessage` dikunci oleh test Step 1 (TDD), bukan ditebak di plan.
