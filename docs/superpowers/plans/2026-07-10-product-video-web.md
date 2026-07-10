# Video Produk — Plan 1: Pipeline Web (Admin + API + Bunny) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admin bisa melampirkan satu video ke produk lewat Edit Produk; video di-transcode Bunny (library terpisah dari feed) dan diekspos oleh product API hanya saat `ready`.

**Architecture:** Modul `lib/product/product-video.ts` mem-mirror `lib/feed/bunny.ts` tapi baca env `BUNNY_PRODUCT_*` (library terpisah — WAJIB, karena GC feed menyapu library-nya). Editor admin punya komponen client mandiri yang persist via endpoint sendiri (`/api/admin/products/[id]/video`) di luar submit form — provision Bunny → TUS resumable upload → webhook `ready`. Logika murni (serialisasi, resolusi webhook, diff orphan GC) diekstrak jadi fungsi teruji; glue UI/route diverifikasi `tsc`+`eslint`+smoke-test manual.

**Tech Stack:** Next.js App Router (server + client), Prisma/PostgreSQL, Bunny Stream (TUS), tus-js-client, ffmpeg.wasm (trim, sudah ada), Node built-in test runner via tsx.

## Global Constraints

- **Library Bunny terpisah**: env `BUNNY_PRODUCT_LIBRARY_ID`, `BUNNY_PRODUCT_API_KEY`, `BUNNY_PRODUCT_CDN_HOSTNAME`, opsional `BUNNY_PRODUCT_WEBHOOK_SECRET`. JANGAN pakai `BUNNY_LIBRARY_ID`/`BUNNY_API_KEY`/`BUNNY_CDN_HOSTNAME` (itu milik feed).
- **JANGAN sentuh kode feed** (`lib/feed/*`, `app/api/feed/*`, cron feed). Boleh meng-IMPORT util video generik dari `lib/feed/` (`video-thumbnail`, `video-trimmer`, `tus-upload`, `video-config.formatFileSize`) — read-only, tidak dimodifikasi.
- **Satu video per produk** (ganti = hapus lalu upload baru).
- Batas: durasi hasil 10–60 detik; ukuran sumber maks `200 * 1024 * 1024` byte; format `video/*`.
- Status video: `"uploading" | "processing" | "ready" | "failed"`; `null` = tidak ada video. Serialisasi ke client HANYA saat `"ready"` + `videoUrl` ada.
- Brand color primary `natalo-600` (#1E5FBF); pakai primitive admin `<Button>`/`<DangerButton>`/`SectionCard`/`ConfirmDialog`/`useAdminToast` yang sudah ada (`components/admin/ui`).
- Auth admin: `getSession("ADMIN")`. CSRF pada mutasi: `assertSameOrigin(request)`.
- Bunny status codes: `CREATED=0, UPLOADED=1, PROCESSING=2, TRANSCODING=3, FINISHED=4, ERROR=5`.
- Verifikasi web per task: `npx tsc --noEmit` + `npx eslint <file>` 0-error. Test murni: `npm test`. Runtime/webhook TIDAK bisa diuji di sandbox (tanpa DATABASE_URL + tanpa Bunny library) → **smoke-test manual = gate sebelum merge**.
- Bekerja di worktree `.claude/worktrees/product-video-spec`, branch `claude/product-video-design`. Commit tiap task; JANGAN commit di working tree utama.

---

## File Structure

**Create:**
- `lib/product/product-video.ts` — klien Bunny library produk: config, create/get/delete/list video, URL builder, TUS credentials.
- `lib/product/product-video-serialize.ts` — fungsi murni: `productVideoPayload()`, `resolveProductVideoWebhookUpdate()`.
- `lib/product/product-video-gc.ts` — `sweepProductVideoOrphans()` + murni `findProductVideoOrphans()`.
- `components/admin/ProductVideoUpload.tsx` — section editor client mandiri.
- `app/api/admin/products/[id]/video/route.ts` — `POST` provision + `PATCH` mark-processing + `DELETE`.
- `app/api/products/bunny/webhook/route.ts` — callback Bunny (verifikasi secret).
- `app/api/cron/product-video-gc/route.ts` — cron GC orphan library produk.
- `tests/product-video-serialize.test.ts` — unit test fungsi murni.
- `tests/product-video-gc.test.ts` — unit test diff orphan.

**Modify:**
- `prisma/schema.prisma` — 5 field video di `model Product`.
- `lib/products.ts` — `StoreProduct` type + `mapProductListRecord` (2 cabang) + `getProductBySlug` mapping.
- `app/admin/(protected)/products/[id]/edit/page.tsx` — render `<ProductVideoUpload>` di SectionCard "Informasi Dasar".
- `vercel.json` — jadwal cron `product-video-gc`.
- `.env.example` (jika ada) — dokumentasi `BUNNY_PRODUCT_*`.

---

## Task 1: Field video di model Product (migrasi Prisma)

**Files:**
- Modify: `prisma/schema.prisma:375` (dalam `model Product`, setelah field `gallery`)

**Interfaces:**
- Produces: kolom `Product.videoUrl`, `Product.videoGuid` (unique), `Product.videoStatus`, `Product.videoThumbnailUrl`, `Product.videoDurationSec` — dipakai semua task berikutnya.

- [ ] **Step 1: Tambahkan field ke schema**

Di `prisma/schema.prisma`, dalam `model Product`, tepat setelah baris `gallery String[] @default([])`, sisipkan:

```prisma
  // Video produk (Bunny Stream, library TERPISAH dari feed — lihat
  // lib/product/product-video.ts). Satu video per produk.
  videoUrl          String? // HLS playlist.m3u8 dari CDN Bunny; null = tidak ada
  videoGuid         String? @unique // GUID Bunny — dipakai webhook + GC produk
  videoStatus       String? // "uploading" | "processing" | "ready" | "failed"
  videoThumbnailUrl String? // auto-thumbnail Bunny, diisi saat ready
  videoDurationSec  Int?
```

- [ ] **Step 2: Generate Prisma Client (offline, tanpa DB)**

Run: `npx prisma generate`
Expected: "Generated Prisma Client" sukses; tipe `Product` sekarang punya field video (dipakai tsc di task lain).

- [ ] **Step 3: Verifikasi schema valid**

Run: `npx prisma validate`
Expected: "The schema at prisma\schema.prisma is valid 🚀"

- [ ] **Step 4: Commit**

```bash
git add prisma/schema.prisma
git commit -m "feat(product-video): field video di model Product + prisma generate"
```

> **DEPLOY GATE (bukan langkah sandbox):** migrasi DB dijalankan di mesin dengan `DATABASE_URL`:
> `npm run prisma:migrate -- --name product_video_fields`
> Sandbox tidak punya DB — `prisma generate` cukup supaya `tsc` hijau; migrasi nyata menyusul di mesin user sebelum merge.

---

## Task 2: Fungsi murni serialisasi + resolusi webhook

**Files:**
- Create: `lib/product/product-video-serialize.ts`
- Test: `tests/product-video-serialize.test.ts`

**Interfaces:**
- Produces:
  - `type ProductVideoFields = { videoUrl: string | null; videoThumbnailUrl: string | null; videoDurationSec: number | null }`
  - `productVideoPayload(p: { videoStatus: string | null; videoUrl: string | null; videoThumbnailUrl: string | null; videoDurationSec: number | null }): ProductVideoFields` — kembalikan URL HANYA saat `videoStatus === "ready"` & `videoUrl` ada; selain itu semua `null`.
  - `type ProductVideoWebhookUpdate = { kind: "processing" } | { kind: "ready"; videoUrl: string; videoThumbnailUrl: string; videoDurationSec: number | null } | { kind: "failed" } | { kind: "ignore" }`
  - `resolveProductVideoWebhookUpdate(input: { status: number; currentStatus: string | null; playlistUrl: string; thumbnailUrl: string; durationSec: number | null }): ProductVideoWebhookUpdate`
- Consumes: konstanta status Bunny (inline, agar file murni tanpa import env).

- [ ] **Step 1: Tulis test yang gagal**

Create `tests/product-video-serialize.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  productVideoPayload,
  resolveProductVideoWebhookUpdate,
} from "../lib/product/product-video-serialize";

test("productVideoPayload: sembunyikan URL saat belum ready", () => {
  assert.deepEqual(
    productVideoPayload({
      videoStatus: "processing",
      videoUrl: "https://cdn/x/playlist.m3u8",
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    }),
    { videoUrl: null, videoThumbnailUrl: null, videoDurationSec: null },
  );
});

test("productVideoPayload: null status → semua null", () => {
  assert.deepEqual(
    productVideoPayload({
      videoStatus: null,
      videoUrl: null,
      videoThumbnailUrl: null,
      videoDurationSec: null,
    }),
    { videoUrl: null, videoThumbnailUrl: null, videoDurationSec: null },
  );
});

test("productVideoPayload: ready → kirim URL", () => {
  assert.deepEqual(
    productVideoPayload({
      videoStatus: "ready",
      videoUrl: "https://cdn/x/playlist.m3u8",
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    }),
    {
      videoUrl: "https://cdn/x/playlist.m3u8",
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    },
  );
});

test("productVideoPayload: ready tapi videoUrl kosong → semua null (guard)", () => {
  assert.deepEqual(
    productVideoPayload({
      videoStatus: "ready",
      videoUrl: null,
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    }),
    { videoUrl: null, videoThumbnailUrl: null, videoDurationSec: null },
  );
});

test("webhook: status non-terminal → processing", () => {
  assert.deepEqual(
    resolveProductVideoWebhookUpdate({
      status: 3,
      currentStatus: "uploading",
      playlistUrl: "https://cdn/x/playlist.m3u8",
      thumbnailUrl: "https://cdn/x/thumbnail.jpg",
      durationSec: 20,
    }),
    { kind: "processing" },
  );
});

test("webhook: sudah settled → ignore (retry)", () => {
  assert.deepEqual(
    resolveProductVideoWebhookUpdate({
      status: 4,
      currentStatus: "ready",
      playlistUrl: "https://cdn/x/playlist.m3u8",
      thumbnailUrl: "https://cdn/x/thumbnail.jpg",
      durationSec: 20,
    }),
    { kind: "ignore" },
  );
});

test("webhook: ERROR → failed", () => {
  assert.deepEqual(
    resolveProductVideoWebhookUpdate({
      status: 5,
      currentStatus: "processing",
      playlistUrl: "https://cdn/x/playlist.m3u8",
      thumbnailUrl: "https://cdn/x/thumbnail.jpg",
      durationSec: 20,
    }),
    { kind: "failed" },
  );
});

test("webhook: FINISHED → ready dengan URL", () => {
  assert.deepEqual(
    resolveProductVideoWebhookUpdate({
      status: 4,
      currentStatus: "processing",
      playlistUrl: "https://cdn/x/playlist.m3u8",
      thumbnailUrl: "https://cdn/x/thumbnail.jpg",
      durationSec: 20,
    }),
    {
      kind: "ready",
      videoUrl: "https://cdn/x/playlist.m3u8",
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    },
  );
});
```

- [ ] **Step 2: Jalankan test — pastikan gagal**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/product/product-video-serialize'`.

- [ ] **Step 3: Implementasi minimal**

Create `lib/product/product-video-serialize.ts`:

```ts
/**
 * Fungsi murni untuk video produk — tanpa import env/DB/Bunny supaya
 * mudah diuji. Dipakai product API (serialisasi) + webhook (resolusi).
 */

// Duplikasi kecil dari status Bunny (lihat lib/feed/bunny.ts) supaya file
// ini tetap murni & tidak coupling ke modul feed.
const BUNNY_FINISHED = 4;
const BUNNY_ERROR = 5;

export type ProductVideoFields = {
  videoUrl: string | null;
  videoThumbnailUrl: string | null;
  videoDurationSec: number | null;
};

const EMPTY: ProductVideoFields = {
  videoUrl: null,
  videoThumbnailUrl: null,
  videoDurationSec: null,
};

/**
 * Kembalikan field video untuk client HANYA saat video benar-benar
 * playable (`ready` + punya URL). Selain itu semua null supaya client
 * lama aman & produk tanpa video tidak bocor URL setengah jadi.
 */
export function productVideoPayload(p: {
  videoStatus: string | null;
  videoUrl: string | null;
  videoThumbnailUrl: string | null;
  videoDurationSec: number | null;
}): ProductVideoFields {
  if (p.videoStatus === "ready" && p.videoUrl) {
    return {
      videoUrl: p.videoUrl,
      videoThumbnailUrl: p.videoThumbnailUrl ?? null,
      videoDurationSec: p.videoDurationSec ?? null,
    };
  }
  return { ...EMPTY };
}

export type ProductVideoWebhookUpdate =
  | { kind: "processing" }
  | {
      kind: "ready";
      videoUrl: string;
      videoThumbnailUrl: string;
      videoDurationSec: number | null;
    }
  | { kind: "failed" }
  | { kind: "ignore" };

/**
 * Petakan callback Bunny → aksi DB. `ignore` saat row sudah settled
 * (webhook retry). Non-terminal → processing. ERROR → failed.
 * FINISHED → ready dengan URL HLS + thumbnail.
 */
export function resolveProductVideoWebhookUpdate(input: {
  status: number;
  currentStatus: string | null;
  playlistUrl: string;
  thumbnailUrl: string;
  durationSec: number | null;
}): ProductVideoWebhookUpdate {
  if (input.currentStatus === "ready" || input.currentStatus === "failed") {
    return { kind: "ignore" };
  }
  if (input.status === BUNNY_ERROR) return { kind: "failed" };
  if (input.status !== BUNNY_FINISHED) return { kind: "processing" };
  return {
    kind: "ready",
    videoUrl: input.playlistUrl,
    videoThumbnailUrl: input.thumbnailUrl,
    videoDurationSec: input.durationSec,
  };
}
```

- [ ] **Step 4: Jalankan test — pastикан lulus**

Run: `npm test`
Expected: semua test `product-video-serialize` PASS.

- [ ] **Step 5: tsc + commit**

Run: `npx tsc --noEmit` → 0 error.
```bash
git add lib/product/product-video-serialize.ts tests/product-video-serialize.test.ts
git commit -m "feat(product-video): fungsi murni serialisasi + resolusi webhook (TDD)"
```

---

## Task 3: Klien Bunny library produk

**Files:**
- Create: `lib/product/product-video.ts`

**Interfaces:**
- Consumes: env `BUNNY_PRODUCT_*`.
- Produces:
  - `type ProductBunnyConfig = { libraryId: string; apiKey: string; cdnHostname: string; webhookSecret: string | null }`
  - `getProductBunnyConfig(): ProductBunnyConfig | null`
  - `isProductBunnyConfigured(): boolean`
  - `createProductVideo(params: { title: string }): Promise<{ guid: string } | { error: string } | null>`
  - `deleteProductVideo(guid: string): Promise<boolean>`
  - `getProductVideo(guid: string): Promise<{ guid: string; status: number; length: number; width: number; height: number; storageSize: number } | null>`
  - `productPlaylistUrl(guid: string): string`
  - `productThumbnailUrl(guid: string): string`
  - `productMp4Url(guid: string, height?: 240 | 360 | 480 | 720 | 1080): string`
  - `generateProductTusCredentials(guid: string, expiryWindowSec?: number): Promise<{ endpoint: string; videoId: string; libraryId: string; authSignature: string; authExpire: number } | null>`
  - `listProductLibraryVideos(page?: number, itemsPerPage?: number): Promise<Array<{ guid: string; storageSize: number }> | null>`
  - `webhookAuthorized(authorizationHeader: string | null): boolean`

- [ ] **Step 1: Implementasi**

Create `lib/product/product-video.ts` (mem-mirror pola `lib/feed/bunny.ts`, env `BUNNY_PRODUCT_*`, TANPA import modul feed):

```ts
/**
 * Klien Bunny Stream untuk VIDEO PRODUK — library TERPISAH dari feed.
 *
 * Pemisahan library WAJIB: cron GC feed (lib/feed/bunny-gc.ts) menghapus
 * SEMUA video di library feed yang tidak direferensikan FeedPost aktif.
 * Kalau video produk berada di library yang sama, GC feed akan
 * menghapusnya. Karena itu modul ini pakai env sendiri dan TIDAK
 * mengimpor apa pun dari lib/feed.
 *
 * Env (set di Vercel):
 *   BUNNY_PRODUCT_LIBRARY_ID
 *   BUNNY_PRODUCT_API_KEY
 *   BUNNY_PRODUCT_CDN_HOSTNAME       (vz-xxxx.b-cdn.net)
 *   BUNNY_PRODUCT_WEBHOOK_SECRET     (opsional)
 */

const BUNNY_API_BASE = "https://video.bunnycdn.com";

export type ProductBunnyConfig = {
  libraryId: string;
  apiKey: string;
  cdnHostname: string;
  webhookSecret: string | null;
};

export function getProductBunnyConfig(): ProductBunnyConfig | null {
  const libraryId = process.env.BUNNY_PRODUCT_LIBRARY_ID;
  const apiKey = process.env.BUNNY_PRODUCT_API_KEY;
  const cdnHostname = process.env.BUNNY_PRODUCT_CDN_HOSTNAME;
  if (!libraryId || !apiKey || !cdnHostname) return null;
  return {
    libraryId,
    apiKey,
    cdnHostname,
    webhookSecret: process.env.BUNNY_PRODUCT_WEBHOOK_SECRET ?? null,
  };
}

export function isProductBunnyConfigured(): boolean {
  return getProductBunnyConfig() !== null;
}

export function webhookAuthorized(authorizationHeader: string | null): boolean {
  const cfg = getProductBunnyConfig();
  if (!cfg?.webhookSecret) return true; // tanpa secret, terima (hanya flip row by guid)
  return (authorizationHeader ?? "") === `Bearer ${cfg.webhookSecret}`;
}

export async function createProductVideo(params: {
  title: string;
}): Promise<{ guid: string } | { error: string } | null> {
  const cfg = getProductBunnyConfig();
  if (!cfg) return null;
  let res: Response;
  try {
    res = await fetch(`${BUNNY_API_BASE}/library/${cfg.libraryId}/videos`, {
      method: "POST",
      headers: {
        AccessKey: cfg.apiKey,
        "Content-Type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify({ title: params.title.slice(0, 200) }),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "network error";
    return { error: `network: ${msg}` };
  }
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return { error: `HTTP ${res.status}: ${text.slice(0, 200) || "no body"}` };
  }
  const data = (await res.json().catch(() => ({}))) as { guid?: string };
  if (!data.guid) return { error: "Response missing guid field" };
  return { guid: data.guid };
}

export async function deleteProductVideo(guid: string): Promise<boolean> {
  const cfg = getProductBunnyConfig();
  if (!cfg || !guid) return false;
  try {
    const res = await fetch(
      `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos/${guid}`,
      { method: "DELETE", headers: { AccessKey: cfg.apiKey } },
    );
    return res.ok;
  } catch {
    return false;
  }
}

export async function getProductVideo(guid: string) {
  const cfg = getProductBunnyConfig();
  if (!cfg) return null;
  try {
    const res = await fetch(
      `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos/${guid}`,
      { headers: { AccessKey: cfg.apiKey, accept: "application/json" } },
    );
    if (!res.ok) return null;
    return (await res.json()) as {
      guid: string;
      status: number;
      length: number;
      width: number;
      height: number;
      storageSize: number;
    };
  } catch {
    return null;
  }
}

export function productPlaylistUrl(guid: string): string {
  const cfg = getProductBunnyConfig();
  if (!cfg) return "";
  return `https://${cfg.cdnHostname}/${guid}/playlist.m3u8`;
}

export function productThumbnailUrl(guid: string): string {
  const cfg = getProductBunnyConfig();
  if (!cfg) return "";
  return `https://${cfg.cdnHostname}/${guid}/thumbnail.jpg`;
}

export function productMp4Url(
  guid: string,
  height: 240 | 360 | 480 | 720 | 1080 = 720,
): string {
  const cfg = getProductBunnyConfig();
  if (!cfg) return "";
  return `https://${cfg.cdnHostname}/${guid}/play_${height}p.mp4`;
}

export async function generateProductTusCredentials(
  guid: string,
  expiryWindowSec: number = 60 * 60,
): Promise<{
  endpoint: string;
  videoId: string;
  libraryId: string;
  authSignature: string;
  authExpire: number;
} | null> {
  const cfg = getProductBunnyConfig();
  if (!cfg) return null;
  const expire = Math.floor(Date.now() / 1000) + expiryWindowSec;
  // SHA256(library_id + api_key + expiration + video_id) — Web Crypto.
  const message = `${cfg.libraryId}${cfg.apiKey}${expire}${guid}`;
  const buffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", buffer);
  const authSignature = Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return {
    endpoint: `${BUNNY_API_BASE}/tusupload`,
    videoId: guid,
    libraryId: cfg.libraryId,
    authSignature,
    authExpire: expire,
  };
}

export async function listProductLibraryVideos(
  page: number = 1,
  itemsPerPage: number = 100,
): Promise<Array<{ guid: string; storageSize: number }> | null> {
  const cfg = getProductBunnyConfig();
  if (!cfg) return null;
  try {
    const res = await fetch(
      `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos?page=${page}&itemsPerPage=${itemsPerPage}&orderBy=date`,
      { headers: { AccessKey: cfg.apiKey, accept: "application/json" } },
    );
    if (!res.ok) return null;
    const data = (await res.json()) as {
      items?: Array<{ guid: string; storageSize: number }>;
    };
    return (data.items ?? []).map((i) => ({
      guid: i.guid,
      storageSize: i.storageSize ?? 0,
    }));
  } catch {
    return null;
  }
}
```

- [ ] **Step 2: tsc + eslint**

Run: `npx tsc --noEmit` → 0 error. `npx eslint lib/product/product-video.ts` → 0 error.

- [ ] **Step 3: Commit**

```bash
git add lib/product/product-video.ts
git commit -m "feat(product-video): klien Bunny library produk (env BUNNY_PRODUCT_*)"
```

---

## Task 4: Endpoint admin — provision / mark-processing / delete

**Files:**
- Create: `app/api/admin/products/[id]/video/route.ts`

**Interfaces:**
- Consumes: `getSession` (`@/lib/auth`), `assertSameOrigin` (`@/lib/csrf`), `prisma` (`@/lib/prisma`), dari `@/lib/product/product-video`: `getProductBunnyConfig`, `createProductVideo`, `deleteProductVideo`, `generateProductTusCredentials`.
- Produces (kontrak untuk `ProductVideoUpload.tsx`):
  - `POST` body `{ videoDurationSec?: number }` → `200 { videoGuid, tus: { endpoint, videoId, libraryId, authSignature, authExpire } }` | `503 { error }` | `404` | `401`.
  - `PATCH` body `{ videoDurationSec?: number }` → set `videoStatus="processing"` → `200 { ok: true }`.
  - `DELETE` → hapus Bunny best-effort + null-kan semua field video → `200 { ok: true }`.

- [ ] **Step 1: Implementasi**

Create `app/api/admin/products/[id]/video/route.ts`:

```ts
/**
 * Endpoint video produk (admin). Persist mandiri di luar submit form
 * Edit Produk karena alur provision→TUS→webhook bersifat async.
 *
 *   POST   → buat video di Bunny library produk, set videoGuid +
 *            videoStatus="uploading", balikan TUS credentials.
 *   PATCH  → tandai upload selesai → videoStatus="processing".
 *   DELETE → hapus video di Bunny + reset semua field video.
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import {
  createProductVideo,
  deleteProductVideo,
  generateProductTusCredentials,
  getProductBunnyConfig,
} from "@/lib/product/product-video";

export const dynamic = "force-dynamic";

function parseDuration(body: unknown): number | null {
  if (!body || typeof body !== "object") return null;
  const raw = (body as Record<string, unknown>).videoDurationSec;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrf = assertSameOrigin(request);
  if (csrf) return csrf;
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const cfg = getProductBunnyConfig();
  if (!cfg) {
    return NextResponse.json(
      { error: "Layanan video produk belum dikonfigurasi." },
      { status: 503 },
    );
  }
  const { id } = await params;
  const product = await prisma.product.findUnique({
    where: { id },
    select: { id: true, name: true, videoGuid: true },
  });
  if (!product) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }

  // Ganti video: bersihkan yang lama dulu (best-effort) supaya tidak orphan.
  if (product.videoGuid) {
    await deleteProductVideo(product.videoGuid);
  }

  const created = await createProductVideo({ title: `product-${product.id}` });
  if (!created || "error" in created) {
    return NextResponse.json(
      { error: created ? created.error : "Bunny tidak tersedia." },
      { status: 502 },
    );
  }
  const tus = await generateProductTusCredentials(created.guid);
  if (!tus) {
    await deleteProductVideo(created.guid);
    return NextResponse.json(
      { error: "Gagal menyiapkan kredensial upload." },
      { status: 502 },
    );
  }

  await prisma.product.update({
    where: { id: product.id },
    data: {
      videoGuid: created.guid,
      videoStatus: "uploading",
      videoDurationSec: parseDuration(await request.json().catch(() => null)),
      videoUrl: null,
      videoThumbnailUrl: null,
    },
  });

  return NextResponse.json({ videoGuid: created.guid, tus });
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrf = assertSameOrigin(request);
  if (csrf) return csrf;
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const body = await request.json().catch(() => null);
  const duration = parseDuration(body);
  const product = await prisma.product.findUnique({
    where: { id },
    select: { id: true, videoGuid: true },
  });
  if (!product?.videoGuid) {
    return NextResponse.json(
      { error: "Belum ada video untuk produk ini." },
      { status: 404 },
    );
  }
  await prisma.product.update({
    where: { id: product.id },
    data: {
      videoStatus: "processing",
      ...(duration ? { videoDurationSec: duration } : {}),
    },
  });
  return NextResponse.json({ ok: true });
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrf = assertSameOrigin(request);
  if (csrf) return csrf;
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const product = await prisma.product.findUnique({
    where: { id },
    select: { id: true, videoGuid: true },
  });
  if (!product) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }
  if (product.videoGuid) {
    await deleteProductVideo(product.videoGuid);
  }
  await prisma.product.update({
    where: { id: product.id },
    data: {
      videoGuid: null,
      videoStatus: null,
      videoUrl: null,
      videoThumbnailUrl: null,
      videoDurationSec: null,
    },
  });
  return NextResponse.json({ ok: true });
}
```

> **CATATAN implementer:** `POST` memanggil `request.json()` di dalam `prisma.update` (baris `parseDuration(await request.json()...)`). Body request hanya bisa dibaca sekali — pindahkan pembacaan ke atas sebelum dipakai:
> ganti urutan jadi `const body = await request.json().catch(() => null);` tepat setelah cek produk, lalu `videoDurationSec: parseDuration(body)`. (Diperbaiki di Step 2 saat tsc/lint bila terlewat.)

- [ ] **Step 2: Perbaiki pembacaan body + tsc + eslint**

Pastikan `POST` membaca `request.json()` sekali di awal (lihat catatan). Run: `npx tsc --noEmit` → 0 error. `npx eslint "app/api/admin/products/[id]/video/route.ts"` → 0 error.

- [ ] **Step 3: Commit**

```bash
git add "app/api/admin/products/[id]/video/route.ts"
git commit -m "feat(product-video): endpoint admin provision/patch/delete"
```

---

## Task 5: Webhook Bunny produk

**Files:**
- Create: `app/api/products/bunny/webhook/route.ts`

**Interfaces:**
- Consumes: `prisma`, dari `@/lib/product/product-video`: `webhookAuthorized`, `getProductVideo`, `productPlaylistUrl`, `productThumbnailUrl`; dari `@/lib/product/product-video-serialize`: `resolveProductVideoWebhookUpdate`.
- Produces: `GET` → `200 { ok: true }` (validasi URL Bunny). `POST` → update `Product` by `videoGuid`.

- [ ] **Step 1: Implementasi**

Create `app/api/products/bunny/webhook/route.ts`:

```ts
/**
 * POST /api/products/bunny/webhook
 *
 * Callback Bunny Stream saat video PRODUK berubah state encoding.
 * Cari Product by videoGuid, resolusi via resolveProductVideoWebhookUpdate.
 *
 * Body Bunny: { VideoLibraryId, VideoGuid, Status }.
 * Auth opsional: BUNNY_PRODUCT_WEBHOOK_SECRET → header Authorization Bearer.
 */

import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  getProductVideo,
  productPlaylistUrl,
  productThumbnailUrl,
  webhookAuthorized,
} from "@/lib/product/product-video";
import { resolveProductVideoWebhookUpdate } from "@/lib/product/product-video-serialize";

export const dynamic = "force-dynamic";

type WebhookPayload = { VideoGuid?: string; Status?: number };

export async function GET() {
  return NextResponse.json({
    ok: true,
    hint: "POST only — menerima callback Bunny Stream video produk.",
  });
}

export async function POST(request: NextRequest) {
  if (!webhookAuthorized(request.headers.get("authorization"))) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }
  const payload = (await request.json().catch(() => null)) as WebhookPayload | null;
  const guid = payload?.VideoGuid;
  const status = payload?.Status;
  if (!guid || typeof status !== "number") {
    return NextResponse.json({ ok: false, error: "Invalid payload" }, { status: 400 });
  }

  const product = await prisma.product.findUnique({
    where: { videoGuid: guid },
    select: { id: true, videoStatus: true },
  });
  if (!product) {
    return NextResponse.json({ ok: true, skipped: "unknown-guid" });
  }

  // Untuk FINISHED, ambil durasi asli dari Bunny (best-effort).
  const meta =
    status === 4 ? await getProductVideo(guid) : null;

  const update = resolveProductVideoWebhookUpdate({
    status,
    currentStatus: product.videoStatus,
    playlistUrl: productPlaylistUrl(guid),
    thumbnailUrl: productThumbnailUrl(guid),
    durationSec: meta?.length ? Math.round(meta.length) : null,
  });

  switch (update.kind) {
    case "ignore":
      return NextResponse.json({ ok: true, skipped: "already-settled" });
    case "processing":
      if (product.videoStatus !== "processing") {
        await prisma.product.update({
          where: { id: product.id },
          data: { videoStatus: "processing" },
        });
      }
      return NextResponse.json({ ok: true, encoded: "processing" });
    case "failed":
      await prisma.product.update({
        where: { id: product.id },
        data: { videoStatus: "failed" },
      });
      return NextResponse.json({ ok: true, encoded: "failed" });
    case "ready":
      await prisma.product.update({
        where: { id: product.id },
        data: {
          videoStatus: "ready",
          videoUrl: update.videoUrl,
          videoThumbnailUrl: update.videoThumbnailUrl,
          videoDurationSec: update.videoDurationSec,
        },
      });
      return NextResponse.json({ ok: true, encoded: "ready" });
  }
}
```

- [ ] **Step 2: tsc + eslint**

Run: `npx tsc --noEmit` → 0 error. `npx eslint app/api/products/bunny/webhook/route.ts` → 0 error.

- [ ] **Step 3: Commit**

```bash
git add app/api/products/bunny/webhook/route.ts
git commit -m "feat(product-video): webhook Bunny produk (status → DB)"
```

---

## Task 6: Komponen editor `ProductVideoUpload`

**Files:**
- Create: `components/admin/ProductVideoUpload.tsx`

**Interfaces:**
- Consumes: `readVideoMetadata` (`@/lib/feed/video-thumbnail`), `formatFileSize` (`@/lib/feed/video-config`), `trimVideo` (`@/lib/feed/video-trimmer`), `uploadToBunnyViaTus` + `BunnyTusCredentials` (`@/lib/feed/tus-upload`), `Button`/`DangerButton`/`ConfirmDialog`/`useAdminToast` (`@/components/admin/ui`). Endpoint dari Task 4.
- Produces: `<ProductVideoUpload productId={string} initial={{ videoStatus, videoThumbnailUrl, videoDurationSec }} />`.

**Konstanta batas (inline di file):**
`MAX_SOURCE = 200 * 1024 * 1024`, `MIN_DURATION = 10`, `MAX_DURATION = 60`, `ACCEPT = "video/mp4,video/quicktime,video/*"`.

- [ ] **Step 1: Implementasi**

Create `components/admin/ProductVideoUpload.tsx`:

```tsx
"use client";

import { useRef, useState } from "react";
import { Button, DangerButton, ConfirmDialog, useAdminToast } from "@/components/admin/ui";
import { readVideoMetadata } from "@/lib/feed/video-thumbnail";
import { formatFileSize } from "@/lib/feed/video-config";
import { trimVideo } from "@/lib/feed/video-trimmer";
import {
  uploadToBunnyViaTus,
  type BunnyTusCredentials,
} from "@/lib/feed/tus-upload";

const MAX_SOURCE = 200 * 1024 * 1024;
const MIN_DURATION = 10;
const MAX_DURATION = 60;
const ACCEPT = "video/mp4,video/quicktime,video/*";

type Initial = {
  videoStatus: string | null;
  videoThumbnailUrl: string | null;
  videoDurationSec: number | null;
};

type Picked = {
  file: File;
  sizeLabel: string;
  width: number;
  height: number;
  durationSec: number;
  qualityLabel: string;
};

function qualityLabel(h: number): string {
  if (h >= 1080) return "HD 1080p";
  if (h >= 720) return "HD 720p";
  if (h >= 480) return "SD 480p";
  return `${h}p`;
}

export function ProductVideoUpload({
  productId,
  initial,
}: {
  productId: string;
  initial: Initial;
}) {
  const { show } = useAdminToast();
  const inputRef = useRef<HTMLInputElement>(null);
  const [status, setStatus] = useState<string | null>(initial.videoStatus);
  const [thumb, setThumb] = useState<string | null>(initial.videoThumbnailUrl);
  const [durationSec, setDurationSec] = useState<number | null>(initial.videoDurationSec);

  const [picked, setPicked] = useState<Picked | null>(null);
  const [pickError, setPickError] = useState<string | null>(null);
  // Trim range
  const [trimStart, setTrimStart] = useState(0);
  const [trimEnd, setTrimEnd] = useState(MAX_DURATION);
  const finalDuration = Math.max(0, trimEnd - trimStart);

  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [stage, setStage] = useState<"" | "trimming" | "uploading">("");
  const [confirmDelete, setConfirmDelete] = useState(false);

  async function onPick(file: File | null) {
    setPickError(null);
    setPicked(null);
    if (!file) return;
    if (!file.type.startsWith("video/")) {
      setPickError("Format video belum didukung. Pilih MP4/MOV/WebM.");
      return;
    }
    if (file.size > MAX_SOURCE) {
      setPickError(
        `Ukuran video ${formatFileSize(file.size)} melebihi batas ${formatFileSize(MAX_SOURCE)}. Rekam lebih pendek atau turunkan ke 1080p.`,
      );
      return;
    }
    try {
      const meta = await readVideoMetadata(file);
      if (meta.durationSec < MIN_DURATION) {
        setPickError(`Durasi terlalu pendek (${Math.round(meta.durationSec)} dtk). Minimal ${MIN_DURATION} detik.`);
        return;
      }
      setPicked({
        file,
        sizeLabel: formatFileSize(file.size),
        width: meta.width,
        height: meta.height,
        durationSec: meta.durationSec,
        qualityLabel: qualityLabel(meta.height),
      });
      setTrimStart(0);
      setTrimEnd(Math.min(meta.durationSec, MAX_DURATION));
    } catch {
      setPickError("Video tidak bisa dibaca. Coba pilih file lain.");
    }
  }

  async function onUpload() {
    if (!picked || uploading) return;
    setUploading(true);
    setProgress(0);
    try {
      // 1) Provision.
      const provRes = await fetch(`/api/admin/products/${productId}/video`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ videoDurationSec: Math.round(finalDuration) }),
      });
      const prov = (await provRes.json().catch(() => ({}))) as {
        videoGuid?: string;
        tus?: BunnyTusCredentials;
        error?: string;
      };
      if (!provRes.ok || !prov.tus) {
        throw new Error(prov.error ?? "Gagal menyiapkan upload.");
      }

      // 2) Trim bila perlu.
      let blob: Blob = picked.file;
      const wantsTrim = trimStart > 0.1 || finalDuration < picked.durationSec - 0.1;
      if (wantsTrim) {
        setStage("trimming");
        setProgress(0);
        blob = await trimVideo(picked.file, {
          trimStartSec: trimStart,
          trimDurationSec: finalDuration,
          onProgress: setProgress,
        });
      }

      // 3) TUS upload.
      setStage("uploading");
      setProgress(0);
      await uploadToBunnyViaTus({
        file: blob,
        credentials: prov.tus,
        filetype: picked.file.type || "video/mp4",
        title: `product-${productId}`,
        onProgress: (pct) => setProgress(pct),
      });

      // 4) Mark processing.
      await fetch(`/api/admin/products/${productId}/video`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ videoDurationSec: Math.round(finalDuration) }),
      });

      setStatus("processing");
      setDurationSec(Math.round(finalDuration));
      setThumb(null);
      setPicked(null);
      show("Video diunggah — sedang diproses Bunny. Muncul di toko setelah selesai.");
    } catch (err) {
      show(err instanceof Error ? err.message : "Upload gagal. Coba lagi.");
    } finally {
      setUploading(false);
      setStage("");
      setProgress(0);
    }
  }

  async function onDelete() {
    setConfirmDelete(false);
    try {
      const res = await fetch(`/api/admin/products/${productId}/video`, {
        method: "DELETE",
      });
      if (!res.ok) throw new Error();
      setStatus(null);
      setThumb(null);
      setDurationSec(null);
      show("Video dihapus.");
    } catch {
      show("Gagal menghapus video.");
    }
  }

  const hasVideo = status === "ready" || status === "processing" || status === "failed";

  return (
    <div className="space-y-3">
      <input
        ref={inputRef}
        type="file"
        accept={ACCEPT}
        className="hidden"
        onChange={(e) => void onPick(e.target.files?.[0] ?? null)}
      />

      {/* State: sudah ada video (ready/processing/failed) & belum pilih file baru */}
      {hasVideo && !picked && (
        <div className="flex items-center gap-3 rounded-xl border border-zinc-200 p-3">
          <div className="relative h-20 w-20 shrink-0 overflow-hidden rounded-lg bg-zinc-100">
            {thumb ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={thumb} alt="Thumbnail video" className="h-full w-full object-cover" />
            ) : (
              <div className="grid h-full w-full place-items-center text-xs text-zinc-400">
                video
              </div>
            )}
          </div>
          <div className="min-w-0 flex-1">
            <StatusBadge status={status} />
            {durationSec ? (
              <p className="mt-1 text-xs text-zinc-500">{durationSec} detik</p>
            ) : null}
          </div>
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" onClick={() => inputRef.current?.click()}>
              Ganti
            </Button>
            <DangerButton size="sm" onClick={() => setConfirmDelete(true)}>
              Hapus
            </DangerButton>
          </div>
        </div>
      )}

      {/* State: kosong & belum pilih */}
      {!hasVideo && !picked && (
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          className="flex w-full flex-col items-center gap-2 rounded-xl border border-dashed border-zinc-300 p-6 text-center transition hover:border-natalo-400 hover:bg-natalo-50/40"
        >
          <span className="text-sm font-semibold text-zinc-700">Tambah Video Produk</span>
          <span className="text-xs text-zinc-500">
            MP4/MOV · {MIN_DURATION}–{MAX_DURATION} detik · maks {formatFileSize(MAX_SOURCE)} · disarankan 1080p
          </span>
        </button>
      )}

      {/* State: file terpilih — kartu info otomatis + trim + upload */}
      {picked && (
        <div className="space-y-3 rounded-xl border border-zinc-200 p-3">
          <div className="flex flex-wrap items-center gap-2 text-xs">
            <span className="rounded-full bg-zinc-100 px-2 py-1 font-semibold text-zinc-700">
              {picked.sizeLabel}
            </span>
            <span className="rounded-full bg-zinc-100 px-2 py-1 font-semibold text-zinc-700">
              {picked.width}×{picked.height}
            </span>
            <span className="rounded-full bg-natalo-50 px-2 py-1 font-semibold text-natalo-700">
              {picked.qualityLabel}
            </span>
            <span className="rounded-full bg-zinc-100 px-2 py-1 font-semibold text-zinc-700">
              {Math.round(picked.durationSec)} dtk
            </span>
          </div>

          {picked.durationSec > MAX_DURATION && (
            <p className="text-xs font-semibold text-amber-600">
              Video lebih dari {MAX_DURATION} detik — atur rentang di bawah (maks {MAX_DURATION} dtk).
            </p>
          )}

          {/* Trim sederhana: dua range slider start/end */}
          <TrimRange
            durationSec={picked.durationSec}
            trimStart={trimStart}
            trimEnd={trimEnd}
            onStart={(v) => setTrimStart(Math.max(0, Math.min(v, trimEnd - MIN_DURATION)))}
            onEnd={(v) =>
              setTrimEnd(
                Math.min(
                  picked.durationSec,
                  Math.min(v, trimStart + MAX_DURATION),
                  Math.max(v, trimStart + MIN_DURATION),
                ),
              )
            }
          />
          <p className="text-xs text-zinc-500">
            Terpilih <span className="font-semibold text-zinc-800">{Math.round(finalDuration)} dtk</span>
          </p>

          {uploading && (
            <div className="space-y-1">
              <div className="h-2 overflow-hidden rounded-full bg-zinc-100">
                <div
                  className="h-full bg-natalo-600 transition-all"
                  style={{ width: `${progress}%` }}
                />
              </div>
              <p className="text-xs text-zinc-500">
                {stage === "trimming" ? "Memotong video…" : "Mengunggah…"} {progress}%
              </p>
            </div>
          )}

          <div className="flex gap-2">
            <Button
              onClick={() => void onUpload()}
              disabled={uploading || finalDuration < MIN_DURATION || finalDuration > MAX_DURATION}
            >
              {uploading ? "Memproses…" : "Unggah Video"}
            </Button>
            <Button variant="ghost" onClick={() => setPicked(null)} disabled={uploading}>
              Batal
            </Button>
          </div>
        </div>
      )}

      {pickError && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">
          {pickError}
        </p>
      )}

      <ConfirmDialog
        open={confirmDelete}
        title="Hapus video produk?"
        message="Video akan dihapus dari toko dan penyimpanan. Tindakan ini tidak bisa dibatalkan."
        confirmLabel="Hapus"
        variant="danger"
        onConfirm={() => void onDelete()}
        onCancel={() => setConfirmDelete(false)}
      />
    </div>
  );
}

function StatusBadge({ status }: { status: string | null }) {
  if (status === "ready")
    return <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-bold text-emerald-700">Tayang</span>;
  if (status === "processing")
    return <span className="rounded-full bg-amber-50 px-2 py-0.5 text-xs font-bold text-amber-700">Sedang diproses…</span>;
  if (status === "failed")
    return <span className="rounded-full bg-red-50 px-2 py-0.5 text-xs font-bold text-red-700">Gagal diproses</span>;
  return null;
}

function TrimRange({
  durationSec,
  trimStart,
  trimEnd,
  onStart,
  onEnd,
}: {
  durationSec: number;
  trimStart: number;
  trimEnd: number;
  onStart: (v: number) => void;
  onEnd: (v: number) => void;
}) {
  return (
    <div className="space-y-2">
      <label className="block text-xs font-medium text-zinc-600">
        Mulai: {Math.round(trimStart)} dtk
        <input
          type="range"
          min={0}
          max={Math.floor(durationSec)}
          step={1}
          value={trimStart}
          onChange={(e) => onStart(Number(e.target.value))}
          className="mt-1 w-full accent-natalo-600"
        />
      </label>
      <label className="block text-xs font-medium text-zinc-600">
        Selesai: {Math.round(trimEnd)} dtk
        <input
          type="range"
          min={0}
          max={Math.floor(durationSec)}
          step={1}
          value={trimEnd}
          onChange={(e) => onEnd(Number(e.target.value))}
          className="mt-1 w-full accent-natalo-600"
        />
      </label>
    </div>
  );
}
```

> **CATATAN implementer:** verifikasi prop `ConfirmDialog` yang benar-benar ada di `components/admin/ui/ConfirmDialog.tsx` (nama prop `open`/`title`/`message`/`confirmLabel`/`variant`/`onConfirm`/`onCancel`). Kalau signature beda, sesuaikan pemanggilan agar cocok — JANGAN ubah ConfirmDialog. Sama untuk `Button` `variant`/`size` dan `useAdminToast().show`. Baca file itu di Step 1 sebelum menulis.

- [ ] **Step 2: Sesuaikan ke API primitive nyata + tsc + eslint**

Baca `components/admin/ui/ConfirmDialog.tsx`, `Button.tsx`, `Toast.tsx`; selaraskan pemanggilan. Run: `npx tsc --noEmit` → 0 error. `npx eslint components/admin/ProductVideoUpload.tsx` → 0 error.

- [ ] **Step 3: Commit**

```bash
git add components/admin/ProductVideoUpload.tsx
git commit -m "feat(product-video): komponen editor upload (deteksi MB/HD + trim + TUS)"
```

---

## Task 7: Pasang section video di Edit Produk

**Files:**
- Modify: `app/admin/(protected)/products/[id]/edit/page.tsx` (SectionCard "Informasi Dasar", di bawah `MultiImageUpload`, sekitar baris 191–247)

**Interfaces:**
- Consumes: `<ProductVideoUpload>` (Task 6). Butuh field video produk tersedia di data yang di-load page (`videoStatus`, `videoThumbnailUrl`, `videoDurationSec`).

- [ ] **Step 1: Import komponen**

Tambah di blok import atas file:
```tsx
import { ProductVideoUpload } from "@/components/admin/ProductVideoUpload";
```

- [ ] **Step 2: Query produk (tidak perlu diubah — sudah terverifikasi)**

Query di file ini (`prisma.product.findUnique({ where: { id }, include: {...} })`, ~baris 27) memakai `include`, BUKAN `select` → semua scalar `Product` (termasuk `videoStatus`/`videoThumbnailUrl`/`videoDurationSec` baru) otomatis ikut. Variabel bernama `product`. **Tidak ada perubahan query.**

- [ ] **Step 3: Render komponen setelah `MultiImageUpload`**

Setelah blok `</...MultiImageUpload>` (dalam SectionCard "Informasi Dasar", sebelum `</SectionCard>` di ~baris 247), sisipkan:
```tsx
              <div className="mt-5 border-t border-zinc-100 pt-4">
                <p className="mb-2 text-sm font-semibold text-zinc-800">Video Produk</p>
                <ProductVideoUpload
                  productId={product.id}
                  initial={{
                    videoStatus: product.videoStatus,
                    videoThumbnailUrl: product.videoThumbnailUrl,
                    videoDurationSec: product.videoDurationSec,
                  }}
                />
              </div>
```
(Sesuaikan nama variabel produk dengan yang dipakai file — cek apakah `product` atau nama lain.)

- [ ] **Step 4: tsc + eslint**

Run: `npx tsc --noEmit` → 0 error. `npx eslint "app/admin/(protected)/products/[id]/edit/page.tsx"` → 0 error.

- [ ] **Step 5: Commit**

```bash
git add "app/admin/(protected)/products/[id]/edit/page.tsx"
git commit -m "feat(product-video): section Video Produk di Edit Produk"
```

---

## Task 8: Serialisasi video di product API (list + detail)

**Files:**
- Modify: `lib/products.ts` — `StoreProduct` type (~baris 36–72), `mapProductListRecord` (2 cabang, ~176–243), `getProductBySlug` mapping.

**Interfaces:**
- Consumes: `productVideoPayload` (Task 2).
- Produces: `StoreProduct` bertambah `videoUrl?`, `videoThumbnailUrl?`, `videoDurationSec?`; terisi HANYA saat `ready`.

- [ ] **Step 1: Import + tambah field ke type**

Di atas `lib/products.ts`, tambah import:
```ts
import { productVideoPayload } from "@/lib/product/product-video-serialize";
```
Di `type StoreProduct`, sebelum `// hanya diisi oleh getProductBySlug`, tambah:
```ts
  /** Video produk (Bunny) — hanya terisi saat encoding "ready". */
  videoUrl?: string | null;
  videoThumbnailUrl?: string | null;
  videoDurationSec?: number | null;
```

- [ ] **Step 2: Isi di kedua cabang `mapProductListRecord`**

`ProductListRecord` sudah memuat semua scalar Product (include, bukan select), jadi `p.videoStatus`/`p.videoUrl`/dll tersedia. Di cabang berVarian (return sekitar baris 176) DAN cabang single (return sekitar 224), tambahkan sebelum penutup objek `return { ... }`:
```ts
      ...productVideoPayload({
        videoStatus: p.videoStatus,
        videoUrl: p.videoUrl,
        videoThumbnailUrl: p.videoThumbnailUrl,
        videoDurationSec: p.videoDurationSec,
      }),
```

- [ ] **Step 3: Isi di `getProductBySlug` (dua cabang)**

`getProductBySlug` (~baris 1056) memuat produk via `include` → record `p` sudah punya semua scalar video (tidak perlu `select`). Ada DUA objek yang di-return: cabang berVarian (`const product: StoreProduct = { ... }`, ~baris 1129) dan cabang single (`const product = { ... }`, ~baris 1175). Di KEDUA objek, tambahkan spread sebelum penutup `}`:
```ts
      ...productVideoPayload({
        videoStatus: p.videoStatus,
        videoUrl: p.videoUrl,
        videoThumbnailUrl: p.videoThumbnailUrl,
        videoDurationSec: p.videoDurationSec,
      }),
```

- [ ] **Step 4: tsc + eslint + test**

Run: `npx tsc --noEmit` → 0 error. `npx eslint lib/products.ts` → 0 error. `npm test` → hijau (regresi test lama).

- [ ] **Step 5: Commit**

```bash
git add lib/products.ts
git commit -m "feat(product-video): serialisasi videoUrl di product API (ready-only)"
```

---

## Task 9: GC orphan library produk (fungsi murni + cron)

**Files:**
- Create: `lib/product/product-video-gc.ts`
- Create: `app/api/cron/product-video-gc/route.ts`
- Test: `tests/product-video-gc.test.ts`
- Modify: `vercel.json` (jadwal cron)

**Interfaces:**
- Produces:
  - `findProductVideoOrphans(referenced: Set<string>, items: { guid: string; storageSize: number }[]): { guid: string; storageSize: number }[]` (murni)
  - `sweepProductVideoOrphans(options?: { dryRun?: boolean }): Promise<{ scanned: number; referenced: number; orphanFound: number; orphanDeleted: number; orphanBytes: number; errors: number }>`
- Consumes: `prisma`, `listProductLibraryVideos`, `deleteProductVideo` (Task 3).

- [ ] **Step 1: Tulis test murni yang gagal**

Create `tests/product-video-gc.test.ts`:
```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { findProductVideoOrphans } from "../lib/product/product-video-gc";

test("findProductVideoOrphans: hanya yang tidak direferensikan", () => {
  const referenced = new Set(["a", "c"]);
  const items = [
    { guid: "a", storageSize: 10 },
    { guid: "b", storageSize: 20 },
    { guid: "c", storageSize: 30 },
    { guid: "d", storageSize: 40 },
  ];
  assert.deepEqual(findProductVideoOrphans(referenced, items), [
    { guid: "b", storageSize: 20 },
    { guid: "d", storageSize: 40 },
  ]);
});

test("findProductVideoOrphans: semua direferensikan → kosong", () => {
  const referenced = new Set(["a", "b"]);
  const items = [
    { guid: "a", storageSize: 1 },
    { guid: "b", storageSize: 2 },
  ];
  assert.deepEqual(findProductVideoOrphans(referenced, items), []);
});
```

- [ ] **Step 2: Jalankan — pastikan gagal**

Run: `npm test`
Expected: FAIL — module `../lib/product/product-video-gc` belum ada.

- [ ] **Step 3: Implementasi GC**

Create `lib/product/product-video-gc.ts`:
```ts
/**
 * Sapu orphan di Bunny library PRODUK — video yang GUID-nya tidak lagi
 * direferensikan oleh Product mana pun (aktif MAUPUN arsip; arsip bisa
 * dipulihkan, videonya jangan dihapus). Orphan datang dari upload
 * gagal/batal di tengah alur.
 */

import { prisma } from "@/lib/prisma";
import {
  deleteProductVideo,
  listProductLibraryVideos,
} from "./product-video";

export function findProductVideoOrphans(
  referenced: Set<string>,
  items: { guid: string; storageSize: number }[],
): { guid: string; storageSize: number }[] {
  return items.filter((it) => !referenced.has(it.guid));
}

export type ProductVideoGcResult = {
  scanned: number;
  referenced: number;
  orphanFound: number;
  orphanDeleted: number;
  orphanBytes: number;
  errors: number;
};

const PAGE_SIZE = 100;

export async function sweepProductVideoOrphans(options?: {
  dryRun?: boolean;
}): Promise<ProductVideoGcResult> {
  const dryRun = options?.dryRun === true;

  const rows = await prisma.product.findMany({
    where: { videoGuid: { not: null } },
    select: { videoGuid: true },
  });
  const referenced = new Set<string>();
  for (const r of rows) if (r.videoGuid) referenced.add(r.videoGuid);

  const result: ProductVideoGcResult = {
    scanned: 0,
    referenced: referenced.size,
    orphanFound: 0,
    orphanDeleted: 0,
    orphanBytes: 0,
    errors: 0,
  };

  let page = 1;
  while (true) {
    const items = await listProductLibraryVideos(page, PAGE_SIZE);
    if (!items) {
      result.errors += 1;
      break;
    }
    if (items.length === 0) break;
    result.scanned += items.length;

    for (const orphan of findProductVideoOrphans(referenced, items)) {
      result.orphanFound += 1;
      result.orphanBytes += orphan.storageSize;
      if (!dryRun) {
        const ok = await deleteProductVideo(orphan.guid);
        if (ok) result.orphanDeleted += 1;
        else result.errors += 1;
      }
    }

    if (items.length < PAGE_SIZE) break;
    page += 1;
    if (page > 50) break; // safety cap 5000 video
  }

  return result;
}
```

- [ ] **Step 4: Jalankan test — pastikan lulus**

Run: `npm test`
Expected: `product-video-gc` PASS.

- [ ] **Step 5: Cron route**

Create `app/api/cron/product-video-gc/route.ts` (pola auth sama dengan `app/api/cron/feed-storage-gc/route.ts`):
```ts
/**
 * GET /api/cron/product-video-gc
 *
 * Sapu orphan Bunny library produk. Auth via CRON_SECRET (Vercel Cron).
 */

import { NextRequest, NextResponse } from "next/server";
import { sweepProductVideoOrphans } from "@/lib/product/product-video-gc";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function isAuthorized(request: NextRequest): boolean {
  const expected = process.env.CRON_SECRET;
  if (!expected) return false;
  return (request.headers.get("authorization") ?? "") === `Bearer ${expected}`;
}

export async function GET(request: NextRequest) {
  if (!isAuthorized(request)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const summary = await sweepProductVideoOrphans({ dryRun: false });
  return NextResponse.json({ ok: true, product: summary });
}
```

- [ ] **Step 6: Jadwalkan di vercel.json**

Di `vercel.json`, dalam array `crons`, tambah entri (mingguan, contoh Senin 03:30 UTC — sesuaikan dengan konvensi cron lain di file):
```json
    { "path": "/api/cron/product-video-gc", "schedule": "30 3 * * 1" }
```

- [ ] **Step 7: tsc + eslint + commit**

Run: `npx tsc --noEmit` → 0 error. `npx eslint lib/product/product-video-gc.ts "app/api/cron/product-video-gc/route.ts"` → 0 error.
```bash
git add lib/product/product-video-gc.ts "app/api/cron/product-video-gc/route.ts" tests/product-video-gc.test.ts vercel.json
git commit -m "feat(product-video): GC orphan library produk + cron"
```

---

## Task 10: Hapus video saat produk dihapus (single + bulk)

**Files:**
- Modify: `app/api/admin/products/bulk/route.ts` (hard-delete path)
- Modify: server action / route hard-delete produk single (cari yang memanggil `prisma.product.delete`)

**Interfaces:**
- Consumes: `deleteProductVideo` (Task 3).

- [ ] **Step 1: Cari titik hard-delete**

Run: `git grep -n "product.delete\|products.*delete\|deleteMany" app/ lib/`
Identifikasi tempat produk benar-benar dihapus (bukan diarsipkan). Bulk sudah ada di `app/api/admin/products/bulk/route.ts`.

- [ ] **Step 2: Sebelum menghapus row, bersihkan video**

Di path hard-delete, sebelum `prisma.product.delete(...)`, ambil `videoGuid` produk yang akan dihapus dan panggil `deleteProductVideo(guid)` best-effort untuk masing-masing. Contoh pola bulk (sesuaikan variabel):
```ts
import { deleteProductVideo } from "@/lib/product/product-video";
// ...
const withVideo = await prisma.product.findMany({
  where: { id: { in: idsToHardDelete }, videoGuid: { not: null } },
  select: { videoGuid: true },
});
await Promise.allSettled(
  withVideo.map((p) => (p.videoGuid ? deleteProductVideo(p.videoGuid) : null)),
);
// ... lalu delete row seperti biasa
```
Jika tidak diberesi di sini, cron GC (Task 9) tetap menyapunya nanti — jadi ini optimasi, bukan wajib untuk kebenaran.

- [ ] **Step 3: tsc + eslint + commit**

Run: `npx tsc --noEmit` → 0 error. `npx eslint app/api/admin/products/bulk/route.ts` → 0 error.
```bash
git add -A
git commit -m "feat(product-video): hapus video Bunny saat produk hard-delete"
```

---

## Task 11: Dokumentasi env + verifikasi akhir

**Files:**
- Modify: `.env.example` (jika ada; kalau tidak, lewati langkah ini)

- [ ] **Step 1: Dokumentasikan env**

Jika ada `.env.example`, tambah:
```
# Video Produk — Bunny Stream LIBRARY TERPISAH dari feed (BUNNY_LIBRARY_ID)
BUNNY_PRODUCT_LIBRARY_ID=
BUNNY_PRODUCT_API_KEY=
BUNNY_PRODUCT_CDN_HOSTNAME=
BUNNY_PRODUCT_WEBHOOK_SECRET=
```

- [ ] **Step 2: Verifikasi menyeluruh**

Run:
- `npx tsc --noEmit` → 0 error
- `npx eslint .` → 0 error (atau minimal 0 error baru pada file yang disentuh)
- `npm test` → semua hijau (termasuk 2 suite baru)

- [ ] **Step 3: Commit akhir**

```bash
git add -A
git commit -m "docs(product-video): env BUNNY_PRODUCT_* di .env.example"
```

> **SMOKE-TEST MANUAL (gate sebelum merge — tidak bisa di sandbox):**
> 1. Buat library Bunny baru (encoding 720p + varian 240/360p, MP4 Fallback ON), set webhook ke `/api/products/bunny/webhook`, isi env `BUNNY_PRODUCT_*` lokal.
> 2. `npm run prisma:migrate -- --name product_video_fields`.
> 3. `npm run dev`, buka Edit Produk → pilih video HP (>60 dtk) → cek kartu MB/resolusi/HD muncul → trim ke ≤60 dtk → Unggah → progress → badge "Sedang diproses…".
> 4. Tunggu webhook → status "Tayang"; cek `GET /api/products/{slug}` memuat `videoUrl` (HLS) + `videoThumbnailUrl`.
> 5. Hapus video → field ter-reset; cek Bunny dashboard video terhapus.

---

## Self-Review

**Spec coverage:**
- Bunny library terpisah + alasan GC → Task 3 (env `BUNNY_PRODUCT_*`), Task 9 (GC sendiri). ✓
- Deteksi otomatis MB/resolusi/durasi → Task 6 (`readVideoMetadata` + `formatFileSize` + kartu info + `qualityLabel`). ✓
- Trim reuse feed → Task 6 (`trimVideo`). ✓
- Auto-thumbnail Bunny → Task 5 (`productThumbnailUrl` saat ready). ✓
- TUS upload → Task 6 (`uploadToBunnyViaTus`) + Task 4 (`generateProductTusCredentials`). ✓
- DB field Product → Task 1. ✓
- Editor section di Informasi Dasar bawah foto → Task 7. ✓
- Endpoint provision/patch/delete + webhook → Task 4, 5. ✓
- Serialisasi ready-only + additive non-breaking → Task 2 + Task 8. ✓
- GC orphan + hard-delete cleanup → Task 9, 10. ✓
- Error handling (env belum set → 503/disabled; upload putus → retry via pilih ulang; webhook telat → status processing) → Task 4 (503), Task 6 (catch+toast), Task 5 (processing). ✓
- Flutter (D1/D2/D3) → **BUKAN plan ini** (Plan 2, lihat catatan penutup). ✓ (sengaja di luar scope)

**Placeholder scan:** tidak ada TBD/TODO; tiap step berisi kode nyata. Dua "CATATAN implementer" (Task 4 body-read, Task 6 API primitive) adalah instruksi verifikasi konkret, bukan placeholder.

**Type consistency:** `productVideoPayload` signature identik di Task 2/8; `BunnyTusCredentials` bentuk sama di Task 3 (`generateProductTusCredentials` return), Task 4 (relay), Task 6 (`uploadToBunnyViaTus`); `resolveProductVideoWebhookUpdate` return `kind` cocok switch di Task 5; `findProductVideoOrphans` signature sama Task 9 test + impl. ✓

## Catatan penutup — Plan 2 (Flutter)

Tampilan app Flutter (grid Beranda autoplay visible-only + detail slide #1 manual play + model/service) ditulis sebagai **Plan 2 terpisah** karena hanya bisa diuji setelah API Plan 1 ter-deploy (deploy gate spec: merge web → rilis Flutter). Plan 2 dibuat setelah Plan 1 selesai/diverifikasi.
