# Customer Chat — Plan 2.5: Proxy Staff-Auth Endpoints (catalog/search + staff-send-image)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menutup dua endpoint proxy yang DITUNDA di Plan 2 §Deferred, dibutuhkan oleh Plan 5 Task 4 (NLCATTER Customer Inbox): `GET /api/catalog/search` (staff cari produk untuk di-share ke chat customer) dan `POST /api/chat/staff-send-image` (staff kirim foto). Keduanya **di-auth Firebase ID token staff** (project `tokochat-a8879`) + gating `owner || canHandleCustomer` — BUKAN sesi customer Natalo.

**Architecture:** Endpoint hidup di Natalo Next.js (repo ini), tapi otoritasnya **staff NLCATTER**: klien NLCATTER mengirim `Authorization: Bearer <Firebase ID token>`; proxy memverifikasi token via Admin SDK tokochat (`getAuth(tokochatApp).verifyIdToken`), lalu membaca `users/{uid}` di Firestore tokochat untuk cek `owner || canHandleCustomer` (paritas `canCS()` Plan 1). `catalog/search` menggunakan kembali query katalog Natalo yang ada lalu memproyeksikan ke **kartu produk customer-safe**. `staff-send-image` = jembatan UploadThing (mirror `feed/upload-photo`), mengembalikan `{url}`; **NLCATTER yang menulis pesan** `type:'image'` ke `customerChats` (punya akses tulis via rules `canCS()`), bukan proxy — proxy stateless untuk foto.

**Tech Stack:** Next.js App Router route handlers, `firebase-admin/auth` (`getAuth`), Admin SDK tokochat (`lib/chat/firestore-admin.ts` dari Plan 2 Task 1), Prisma (baca `Product`), `lib/products.ts` (`mapProductListRecord`/`StoreProduct`), `lib/product-pricing.ts` (`resolveActiveDiscount`), UploadThing (`uploadToUT`), `validateImageMagicBytes`, Node test runner via `tsx` (`node:test`).

## Global Constraints

- **Auth = Firebase ID token staff**, BUKAN `getSession('CUSTOMER')`. Header `Authorization: Bearer <idToken>`. Verifikasi WAJIB server-side; gating `owner || canHandleCustomer` (paritas `canCS()` Plan 1). Tolak 401 (token invalid/absen) / 403 (bukan staff berhak).
- **CSRF:** endpoint ini dipanggil app native NLCATTER (bukan browser same-origin) → `assertSameOrigin` TIDAK dipakai; keamanan dari verifikasi ID token. (Beda dari endpoint customer di Plan 2 yang pakai CSRF.)
- **Reuse Admin app yang ADA:** perpanjang `lib/chat/firestore-admin.ts` (Plan 2 Task 1, app bernama `tokochat`) untuk mengekspor `getTokochatAuth()` — JANGAN buat app kedua/`tokochat-admin` baru; pakai app `tokochat` yang sama.
- **catalog/search customer-safe:** hanya field kartu — `{productId, slug, name, imageUrl, price, discountPrice, stock, isAvailable, brand}`. JANGAN bocorkan field internal (cost/margin/supplier/aggregate internal). Sertakan produk `stock<=0` TAPI tandai `isAvailable:false` (picker NLCATTER men-disable-nya; server share tetap menolak `stock<=0` — dua lapis, sisi tulis pesan).
- **Reuse logika katalog** yang ada (`lib/products.ts` `mapProductListRecord` + query `app/api/products/route.ts`), jangan tulis ulang query/harga; proyeksikan hasilnya ke kartu.
- **staff-send-image = jembatan UploadThing saja** (mirror `feed/upload-photo`: jpeg/png/webp, MAX 8MB, `validateImageMagicBytes`, `uploadToUT(file, prefix)`); kembalikan `{url}`. Penulisan pesan Firestore dilakukan NLCATTER (Plan 5), bukan di sini.
- Kontrak selaras Plan 5: `GET /api/catalog/search?q=...` → `{ items: CatalogCard[] }`; `POST /api/chat/staff-send-image` (multipart `file`) → `{ url }`.
- Env `TOKOCHAT_*` sudah dideklarasikan di Plan 2 Task 1 — tak ada env baru.
- Semua path relatif ke root repo Natalo (`C:/Users/USER/Desktop/natalopetshopflutter`).

---

## File Structure

- `lib/chat/firestore-admin.ts` — **modify**: tambah `getTokochatAuth()` (reuse app `tokochat`).
- `lib/chat/staff-auth.ts` — **create**: `verifyStaffRequest(request)` → `{ uid }` | `NextResponse` (401/403); helper murni `isStaffAuthorized(userDoc)`.
- `lib/chat/catalog-card.ts` — **create**: `toCatalogCard(storeProduct)` murni → proyeksi customer-safe + `isAvailable`.
- `app/api/catalog/search/route.ts` — **create**: `GET` (auth staff → cari produk → kartu).
- `app/api/chat/staff-send-image/route.ts` — **create**: `POST` (auth staff → multipart → uploadToUT → `{url}`).
- `tests/chat-staff-auth.test.ts` — **create**: uji `isStaffAuthorized`.
- `tests/chat-catalog-card.test.ts` — **create**: uji `toCatalogCard` (allowlist + stok/isAvailable).

---

### Task 1: Verifikasi staff (Firebase ID token + canHandleCustomer) — TDD

**Files:**
- Modify: `lib/chat/firestore-admin.ts`
- Create: `lib/chat/staff-auth.ts`, `tests/chat-staff-auth.test.ts`

**Interfaces:**
- `getTokochatAuth(): Auth` — `getAuth(getTokochatApp())` (reuse app `tokochat`).
- `isStaffAuthorized(userDoc: { role?; canHandleCustomer? } | null): boolean` — **murni**: `role==='owner' || canHandleCustomer===true`. Dipakai handler & diuji.
- `verifyStaffRequest(request): Promise<{ uid: string } | NextResponse>` — ambil Bearer, `verifyIdToken`, baca `users/{uid}` tokochat, cek `isStaffAuthorized`; kembalikan `{uid}` atau `NextResponse` 401/403.

- [ ] **Step 1: Tambah `getTokochatAuth` ke `lib/chat/firestore-admin.ts`**

```ts
import { getAuth, type Auth } from "firebase-admin/auth";
// ... (getTokochatApp sudah ada dari Plan 2 Task 1)
let cachedAuth: Auth | null = null;
export function getTokochatAuth(): Auth {
  if (cachedAuth) return cachedAuth;
  cachedAuth = getAuth(getTokochatApp());
  return cachedAuth;
}
```

- [ ] **Step 2: Tulis test murni** (`tests/chat-staff-auth.test.ts`)

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { isStaffAuthorized } from "@/lib/chat/staff-auth";

test("owner selalu boleh", () => {
  assert.equal(isStaffAuthorized({ role: "owner" }), true);
});
test("karyawan + canHandleCustomer boleh", () => {
  assert.equal(isStaffAuthorized({ role: "karyawan", canHandleCustomer: true }), true);
});
test("karyawan tanpa flag ditolak", () => {
  assert.equal(isStaffAuthorized({ role: "karyawan" }), false);
  assert.equal(isStaffAuthorized({ role: "karyawan", canHandleCustomer: false }), false);
});
test("doc null / kosong ditolak", () => {
  assert.equal(isStaffAuthorized(null), false);
  assert.equal(isStaffAuthorized({}), false);
});
```

- [ ] **Step 3: Jalankan — GAGAL.** `npm test`.

- [ ] **Step 4: Implementasi `lib/chat/staff-auth.ts`**

```ts
import { NextResponse } from "next/server";
import { getTokochatAuth, getTokochatFirestore } from "@/lib/chat/firestore-admin";

export function isStaffAuthorized(
  userDoc: { role?: string; canHandleCustomer?: boolean } | null,
): boolean {
  if (!userDoc) return false;
  return userDoc.role === "owner" || userDoc.canHandleCustomer === true;
}

export async function verifyStaffRequest(
  request: Request,
): Promise<{ uid: string } | NextResponse> {
  const header = request.headers.get("authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return NextResponse.json({ error: "Token wajib." }, { status: 401 });
  let uid: string;
  try {
    uid = (await getTokochatAuth().verifyIdToken(token)).uid;
  } catch {
    return NextResponse.json({ error: "Token tidak valid." }, { status: 401 });
  }
  const snap = await getTokochatFirestore().doc(`users/${uid}`).get();
  if (!isStaffAuthorized(snap.exists ? (snap.data() as Record<string, unknown>) : null)) {
    return NextResponse.json({ error: "Tidak berhak menangani customer." }, { status: 403 });
  }
  return { uid };
}
```

- [ ] **Step 5: Jalankan — LULUS.** `npm test`.

- [ ] **Step 6: Commit**

```bash
git add lib/chat/firestore-admin.ts lib/chat/staff-auth.ts tests/chat-staff-auth.test.ts
git commit -m "feat(chat): verifikasi staff Firebase ID token + gating canHandleCustomer"
```

---

### Task 2: `GET /api/catalog/search` (kartu produk customer-safe) — TDD

**Files:**
- Create: `lib/chat/catalog-card.ts`, `app/api/catalog/search/route.ts`, `tests/chat-catalog-card.test.ts`

**Interfaces:**
- `toCatalogCard(p: StoreProduct): CatalogCard` — **murni**: pilih hanya `{productId, slug, name, imageUrl, price, discountPrice, stock, isAvailable, brand}`; `isAvailable = stock > 0`. Sumber `StoreProduct` = `lib/products.ts` (`mapProductListRecord`, sudah menghitung harga diskon via `resolveActiveDiscount`).

- [ ] **Step 1: Test murni** (`tests/chat-catalog-card.test.ts`)
- `toCatalogCard` menghasilkan HANYA field allowlist (assert tak ada field internal: mis. `cost`, `margin`, atau field StoreProduct lain yang tak diinginkan — cek `Object.keys` === set yang diharapkan).
- `isAvailable` true saat `stock>0`, false saat `stock===0`.
- `discountPrice` null bila StoreProduct tak punya diskon aktif; angka bila ada.

> Konstruksi input `StoreProduct` sesuai bentuk `lib/products.ts:36-72`. Uji proyeksi, bukan query DB.

- [ ] **Step 2: Jalankan — GAGAL.**

- [ ] **Step 3: Implementasi `lib/chat/catalog-card.ts`** (proyeksi allowlist) + **`app/api/catalog/search/route.ts`**:
  - `const auth = await verifyStaffRequest(request); if (auth instanceof NextResponse) return auth;`
  - **Kill-switch (fix C1):** `if (!(await isChatEnabled())) return NextResponse.json({ error: "Chat sedang nonaktif." }, { status: 503 });` (impor `isChatEnabled` dari `app/api/chat/config/route.ts`) — simetris dgn endpoint customer Plan 2; jangan biarkan staff share produk saat chat mati.
  - Ambil `q`/paging dari query. **Gunakan kembali** jalur query produk yang ada (panggil fungsi listing yang dipakai `app/api/products/route.ts` / `lib/products.ts` `mapProductListRecord`) — JANGAN tulis ulang query harga/stok.
  - Map hasil → `toCatalogCard`. **Jangan** filter `stock<=0` di sini (picker perlu menampilkannya sebagai disabled) — cukup `isAvailable:false`.
  - `return NextResponse.json({ items })`.
  - `export const dynamic = "force-dynamic";`

- [ ] **Step 4: Jalankan — LULUS.** `npm test`; `npm run lint` bersih.

- [ ] **Step 5: Commit**

```bash
git add lib/chat/catalog-card.ts app/api/catalog/search/route.ts tests/chat-catalog-card.test.ts
git commit -m "feat(chat): GET /api/catalog/search (staff) kartu produk customer-safe"
```

---

### Task 3: `POST /api/chat/staff-send-image` (jembatan UploadThing)

**Files:**
- Create: `app/api/chat/staff-send-image/route.ts`

**Interfaces:**
- Consumes: `verifyStaffRequest` (Task 1), `validateImageMagicBytes`, `uploadToUT`. Mirror `app/api/feed/upload-photo/route.ts`.

- [ ] **Step 1: Buat handler**
  - `const auth = await verifyStaffRequest(request); if (auth instanceof NextResponse) return auth;`
  - **Kill-switch (fix C1):** `if (!(await isChatEnabled())) return NextResponse.json({ error: "Chat sedang nonaktif." }, { status: 503 });` (impor `isChatEnabled` dari `app/api/chat/config/route.ts`).
  - `const form = await request.formData(); const file = form.get("file") as File | null;` → 400 bila kosong.
  - MIME allowlist `image/jpeg|png|webp` → 400; ukuran > 8MB → 413; `validateImageMagicBytes(Buffer.from(await file.arrayBuffer()), file.type)` → 415.
  - `const { url } = await uploadToUT(file, `custchat-${auth.uid}`);`
  - `return NextResponse.json({ url });`
  - `export const dynamic = "force-dynamic";` (tanpa `assertSameOrigin` — native app, bukan browser).

- [ ] **Step 2: Verifikasi** — `npm run lint` bersih; `npm test` (helper tetap hijau).

- [ ] **Step 3: Commit**

```bash
git add app/api/chat/staff-send-image/route.ts
git commit -m "feat(chat): POST /api/chat/staff-send-image (staff auth) jembatan UploadThing"
```

---

## Definition of Done (Plan 2.5)

- [ ] `npm test` hijau: `chat-staff-auth`, `chat-catalog-card` (+ test existing tetap hijau).
- [ ] `lib/chat/firestore-admin.ts` mengekspor `getTokochatAuth()` (reuse app `tokochat`, bukan app baru).
- [ ] `verifyStaffRequest` menolak token invalid (401) & non-staff/tanpa flag (403); `isStaffAuthorized` = `owner||canHandleCustomer`.
- [ ] `GET /api/catalog/search` (auth staff) → `{items}` kartu customer-safe; `stock<=0` tetap muncul dgn `isAvailable:false`; tak ada field internal.
- [ ] `POST /api/chat/staff-send-image` (auth staff) → `{url}`; validasi MIME/size/magic-bytes; tanpa CSRF.
- [ ] Kedua endpoint cek kill-switch `isChatEnabled` → 503 saat chat off (fix C1, simetris Plan 2).
- [ ] Tak ada env baru; tak ada `firebase deploy`.

## Self-Review (penulis plan)

- **Grounding (build-sheet terverifikasi):** `Product`/`StoreProduct`/`mapProductListRecord` (`lib/products.ts:36-72,149-247`), `resolveActiveDiscount` (`lib/product-pricing.ts:42-88`), stok `hasVariants`→SUM varian, `getAuth().verifyIdToken` + baca `users/{uid}`, upload `feed/upload-photo` (jpeg/png/webp, 8MB, `validateImageMagicBytes`, `uploadToUT`→{url,key}) — semua diverifikasi ke source, nol nilai mengarang. ✓
- **Konsistensi lintas-plan:** perpanjang app `tokochat` Plan 2 (bukan app baru); gating `owner||canHandleCustomer` = paritas `canCS()` Plan 1; kontrak `{items}`/`{url}` selaras Plan 5 Task 4; penulisan pesan foto oleh NLCATTER (Plan 5), proxy stateless. ✓
- **Keamanan:** auth ID token staff (bukan sesi customer); allowlist kartu produk (tak bocor field internal); guard stok dua lapis (isAvailable + tolak share saat tulis); tanpa CSRF karena klien native (keamanan dari verifikasi token). ✓
- **Batas uji:** logika murni (`isStaffAuthorized`, `toCatalogCard`) teruji `node:test`; verifikasi token/upload nyata diuji manual/integrasi (butuh kredensial tokochat + ID token staff).
- **Menutup dependency:** endpoint ini adalah prasyarat Plan 5 Task 4 (Bagikan Produk + foto staff) — sekarang terencana penuh.
