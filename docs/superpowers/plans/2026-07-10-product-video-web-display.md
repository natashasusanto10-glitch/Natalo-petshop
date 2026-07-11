# Video Produk — Plan (Web Storefront Display) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Tampilkan video produk di web natalopetshop.com — grid (Katalog + Beranda) autoplay bisu visible-only, dan galeri detail dengan video sebagai slide #1 (manual play).

**Architecture:** Frontend-only, TANPA perubahan API/DB. `StoreProduct` sudah membawa `videoUrl`/`videoThumbnailUrl`/`videoDurationSec` (ready-only). Web memutar **MP4 progresif Bunny** (bukan HLS) yang di-derive dari URL playlist via helper murni. Grid: satu komponen `ProductCard` dipakai Katalog & Beranda (HomeProductCard hanya mem-forward ke ProductCard) → cukup ubah area media-nya jadi klien saat ada video. Detail: `ProductImageCarousel` ditambah slot video slide #1.

**Tech Stack:** Next.js App Router (server + client components), next/image, IntersectionObserver, HTML5 `<video>`, Node test runner via tsx.

## Global Constraints

- TANPA perubahan API atau schema/DB (murni tampilan). Risiko rendah.
- Video hanya muncul saat `product.videoUrl` (dan `videoThumbnailUrl`) terisi — API sudah menjamin itu HANYA saat status "ready".
- Web pakai **MP4 progresif** (`play_<h>p.mp4`), bukan HLS `.m3u8` — supaya jalan di semua browser tanpa hls.js. Grid = 360p, Detail = 720p. Bergantung Bunny "MP4 Fallback" ON; kalau MP4 gagal load → **fallback ke foto** (grid) / tetap tampil thumbnail (detail). JANGAN pernah kotak hitam.
- Grid autoplay: **muted, loop, playsInline, visible-only** (IntersectionObserver), dengan **batas jumlah video main bersamaan** (registry). Detail: **manual play** (klik), dengan kontrol + suara, TANPA autoplay; pause saat pindah slide.
- Brand: harga `#1E5FBF`; badge tetap gaya existing. JANGAN ubah layout kartu/harga/CTA yang sudah ada — hanya area media.
- JANGAN sentуह `lib/feed/*`. Helper URL video milik produk sendiri (murni, tanpa env).
- Verifikasi per task: `npx tsc --noEmit` + `npx eslint <file>` 0-error; `npm test` hijau. `next build` TIDAK bisa di sandbox (butuh DB) → smoke-test manual di preview = gate.
- Kerja di worktree `.claude/worktrees/product-video-web`, branch `claude/product-video-web-display`. Commit tiap task. JANGAN commit di main tree.

## File Structure

**Create:**
- `lib/product/product-video-url.ts` — pure `productVideoMp4(playlistUrl, height)` (derive MP4 URL).
- `components/product/ProductCardVideo.tsx` — client: autoplay bisu visible-only + fallback foto.
- `components/product/video-autoplay-registry.ts` — client module: batasi jumlah video main bersamaan.
- `tests/product-video-url.test.ts` — unit test helper.

**Modify:**
- `components/ProductCard.tsx` — area media: render `<ProductCardVideo>` saat ada video, else `<Image>` (kedua varian: default + compact).
- `components/ProductImageCarousel.tsx` — prop opsional `video`; render slide #1 video (thumbnail + ▶, manual).
- `app/products/[slug]/page.tsx` — hitung `video` dari `product.videoUrl` (→ mp4 720p) + pass ke carousel.

---

## Task 1: Helper murni MP4-URL (TDD)

**Files:** Create `lib/product/product-video-url.ts`; Test `tests/product-video-url.test.ts`.

**Interfaces:**
- Produces: `productVideoMp4(playlistUrl: string | null | undefined, height?: 240|360|480|720|1080): string | null` — rewrite `.../<guid>/playlist.m3u8[?q]` → `.../<guid>/play_<h>p.mp4[?q]`; `null` kalau bukan URL playlist Bunny atau input kosong.

- [ ] **Step 1: Test gagal**

Create `tests/product-video-url.test.ts`:
```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { productVideoMp4 } from "../lib/product/product-video-url";

test("null/undefined/empty → null", () => {
  assert.equal(productVideoMp4(null), null);
  assert.equal(productVideoMp4(undefined), null);
  assert.equal(productVideoMp4(""), null);
});

test("playlist → mp4 default 720p", () => {
  assert.equal(
    productVideoMp4("https://vz-abc.b-cdn.net/1a2b-3c/playlist.m3u8"),
    "https://vz-abc.b-cdn.net/1a2b-3c/play_720p.mp4",
  );
});

test("height 360", () => {
  assert.equal(
    productVideoMp4("https://vz-abc.b-cdn.net/1a2b-3c/playlist.m3u8", 360),
    "https://vz-abc.b-cdn.net/1a2b-3c/play_360p.mp4",
  );
});

test("preserves query string", () => {
  assert.equal(
    productVideoMp4("https://vz-abc.b-cdn.net/1a2b-3c/playlist.m3u8?token=x&expires=1", 240),
    "https://vz-abc.b-cdn.net/1a2b-3c/play_240p.mp4?token=x&expires=1",
  );
});

test("non-playlist / non-bunny URL → null", () => {
  assert.equal(productVideoMp4("https://example.com/video.mp4"), null);
  assert.equal(productVideoMp4("https://vz-abc.b-cdn.net/1a2b-3c/thumbnail.jpg"), null);
});
```

- [ ] **Step 2: Jalankan → FAIL** — `npm test` → "Cannot find module".

- [ ] **Step 3: Implementasi**

Create `lib/product/product-video-url.ts`:
```ts
/**
 * Derive URL MP4 progresif Bunny dari URL playlist HLS produk.
 *
 * Product API menyimpan videoUrl sebagai playlist HLS (.m3u8). Browser
 * (selain Safari) tak memutar HLS natif, jadi untuk web kita pakai MP4
 * progresif (play_<h>p.mp4) yang jalan di semua browser tanpa hls.js.
 * Rewrite murni string (host + guid tetap), jadi tak butuh env/library.
 * Butuh "MP4 Fallback" ON di library Bunny; kalau file MP4 tak ada,
 * pemutar akan error → caller fallback ke foto/thumbnail.
 *
 * Return null kalau URL bukan pola playlist Bunny (`/<guid>/playlist.m3u8`),
 * supaya caller bisa fallback aman.
 */
export function productVideoMp4(
  playlistUrl: string | null | undefined,
  height: 240 | 360 | 480 | 720 | 1080 = 720,
): string | null {
  if (!playlistUrl) return null;
  const m = playlistUrl.match(
    /^(https?:\/\/[^/]+\/[a-f0-9-]+\/)playlist\.m3u8(\?.*)?$/i,
  );
  if (!m) return null;
  return `${m[1]}play_${height}p.mp4${m[2] ?? ""}`;
}
```

- [ ] **Step 4: Jalankan → PASS** — `npm test` (semua hijau). `npx tsc --noEmit` 0-error.

- [ ] **Step 5: Commit**
```bash
git add lib/product/product-video-url.ts tests/product-video-url.test.ts
git commit -m "feat(product-video-web): helper murni derive MP4 URL dari playlist (TDD)"
```

---

## Task 2: Grid autoplay — komponen video + registry konkurensi

**Files:** Create `components/product/video-autoplay-registry.ts`, `components/product/ProductCardVideo.tsx`.

**Interfaces:**
- Produces:
  - registry: `requestPlay(id: string): boolean` (true kalau dapat slot), `releasePlay(id: string): void`. Batas `MAX_CONCURRENT = 4`.
  - `<ProductCardVideo mp4Url={string} poster={string|null} alt={string} className?={string} />` — client component.

- [ ] **Step 1: Registry**

Create `components/product/video-autoplay-registry.ts`:
```ts
"use client";
/**
 * Batasi jumlah video grid yang autoplay bersamaan supaya decoder browser
 * / HP tidak kehabisan (banyak <video> main sekaligus = janky/crash).
 * Sederhana: Set global berisi id yang sedang main, maks MAX_CONCURRENT.
 */
const MAX_CONCURRENT = 4;
const playing = new Set<string>();

export function requestPlay(id: string): boolean {
  if (playing.has(id)) return true;
  if (playing.size >= MAX_CONCURRENT) return false;
  playing.add(id);
  return true;
}

export function releasePlay(id: string): void {
  playing.delete(id);
}
```

- [ ] **Step 2: Komponen video kartu**

Create `components/product/ProductCardVideo.tsx`:
```tsx
"use client";

import Image from "next/image";
import { useEffect, useId, useRef, useState } from "react";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { releasePlay, requestPlay } from "./video-autoplay-registry";

/**
 * Area media kartu produk saat ada video: foto cover sebagai dasar +
 * <video> bisu/loop yang autoplay HANYA saat kartu terlihat (visible-only)
 * dan mendapat slot dari registry konkurensi. Kalau video gagal / belum
 * siap / tak dapat slot → tetap tampil foto. Tak pernah kotak hitam.
 */
export function ProductCardVideo({
  mp4Url,
  poster,
  alt,
  className = "",
}: {
  mp4Url: string;
  poster: string | null;
  alt: string;
  className?: string;
}) {
  const id = useId();
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [canPlay, setCanPlay] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const wrap = wrapRef.current;
    const video = videoRef.current;
    if (!wrap || !video || failed) return;

    let inView = false;
    const tryPlay = () => {
      if (!inView) return;
      if (!requestPlay(id)) return;
      video.play().then(() => setCanPlay(true)).catch(() => releasePlay(id));
    };
    const stop = () => {
      video.pause();
      releasePlay(id);
    };

    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          inView = e.isIntersecting && e.intersectionRatio >= 0.6;
          if (inView) tryPlay();
          else stop();
        }
      },
      { threshold: [0, 0.6] },
    );
    io.observe(wrap);
    return () => {
      io.disconnect();
      stop();
    };
  }, [id, failed]);

  return (
    <div ref={wrapRef} className={`absolute inset-0 ${className}`}>
      {poster ? (
        <Image
          src={poster}
          alt={alt}
          fill
          placeholder="blur"
          blurDataURL={IMAGE_BLUR_GRAY}
          sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 25vw"
          className="object-cover"
        />
      ) : (
        <div className="flex h-full items-center justify-center text-5xl text-gray-300">🐾</div>
      )}
      {!failed && (
        <video
          ref={videoRef}
          src={mp4Url}
          muted
          loop
          playsInline
          preload="none"
          aria-hidden="true"
          onError={() => setFailed(true)}
          className={`absolute inset-0 h-full w-full object-cover transition-opacity duration-300 ${
            canPlay ? "opacity-100" : "opacity-0"
          }`}
        />
      )}
      {!failed && (
        <span className="pointer-events-none absolute bottom-1.5 right-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-black/55 text-white">
          <svg viewBox="0 0 24 24" fill="currentColor" className="h-3 w-3" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
        </span>
      )}
    </div>
  );
}
```

- [ ] **Step 3: tsc + eslint 0-error** (`npx tsc --noEmit`, `npx eslint components/product/ProductCardVideo.tsx components/product/video-autoplay-registry.ts`).

- [ ] **Step 4: Commit**
```bash
git add components/product/ProductCardVideo.tsx components/product/video-autoplay-registry.ts
git commit -m "feat(product-video-web): komponen grid autoplay visible-only + registry konkurensi"
```

---

## Task 3: Pasang video ke area media ProductCard (Katalog + Beranda)

**Files:** Modify `components/ProductCard.tsx`.

**Interfaces:** Consumes `productVideoMp4` (Task 1), `<ProductCardVideo>` (Task 2). `HomeProductCard` mem-forward ke `ProductCard`, jadi perubahan ini otomatis kena Beranda juga.

- [ ] **Step 1: Import + derive**

Di atas `components/ProductCard.tsx` tambah:
```tsx
import { productVideoMp4 } from "@/lib/product/product-video-url";
import { ProductCardVideo } from "./product/ProductCardVideo";
```
Di dalam `ProductCard`, setelah baris `const discountPercent = ...`, tambah:
```tsx
  const gridVideoMp4 = productVideoMp4(product.videoUrl, 360);
```

- [ ] **Step 2: Varian compact — area media**

Di blok compact, ganti isi div gambar (`product.imageUrl ? <Image.../> : <div>🐾</div>`) menjadi: kalau `gridVideoMp4` ada → `<ProductCardVideo mp4Url={gridVideoMp4} poster={product.imageUrl} alt={product.name} />`, else render `<Image>`/placeholder yang sekarang. Contoh:
```tsx
{gridVideoMp4 ? (
  <ProductCardVideo mp4Url={gridVideoMp4} poster={product.imageUrl} alt={product.name} />
) : product.imageUrl ? (
  <Image /* ...props existing... */ />
) : (
  <div className="flex h-full items-center justify-center text-4xl text-gray-300">🐾</div>
)}
```
(Container-nya sudah `relative aspect-square ... overflow-hidden`; ProductCardVideo `absolute inset-0` pas.)

- [ ] **Step 3: Varian default — area media**

Lakukan hal sama di blok default (div `relative aspect-square rounded-2xl bg-white`): kalau `gridVideoMp4` → `<ProductCardVideo>`, else `<Image>`/placeholder existing. Pertahankan badge (Member/rank/badge) yang ada — mereka tetap di atas media (absolute), tidak perlu diubah.

- [ ] **Step 4: tsc + eslint + test** — `npx tsc --noEmit` 0; `npx eslint components/ProductCard.tsx` 0; `npm test` hijau (regresi `product-card-discount.test.ts` dll).

- [ ] **Step 5: Commit**
```bash
git add components/ProductCard.tsx
git commit -m "feat(product-video-web): grid Katalog+Beranda autoplay video saat ada"
```

---

## Task 4: Galeri detail — video slide #1 (manual play)

**Files:** Modify `components/ProductImageCarousel.tsx`, `app/products/[slug]/page.tsx`.

**Interfaces:** `ProductImageCarousel` dapat prop baru `video?: { mp4Url: string; thumbnailUrl: string; durationSec: number | null }`. Saat ada, slide #0 = video.

- [ ] **Step 1: Tambah prop + slide video di carousel**

Di `components/ProductImageCarousel.tsx`:
- Tambah ke `Props`: `video?: { mp4Url: string; thumbnailUrl: string; durationSec: number | null };`.
- Bentuk daftar slide gabungan: `const slides = [...(video ? [{ kind: "video" as const }] : []), ...safeImages.map((src) => ({ kind: "image" as const, src }))];`. `showIndicators = slides.length > 1`.
- State play: `const [videoPlaying, setVideoPlaying] = useState(false);` + `videoElRef`.
- Render map atas `slides` (bukan `safeImages`), `data-index` per slide. Untuk slide `video`:
  - Kalau belum play: thumbnail (`<Image src={video.thumbnailUrl} fill className="object-cover">`) + overlay tombol ▶ besar di tengah + badge durasi (`formatClock(video.durationSec)` pojok kanan-atas) + badge "Video". Klik → `setVideoPlaying(true)` lalu `videoElRef.current?.play()`.
  - Kalau sudah play: `<video ref={videoElRef} src={video.mp4Url} controls playsInline className="h-full w-full object-contain bg-black" onError={...tampilkan thumbnail lagi...} />`.
  - JANGAN buka ProductImageViewer untuk slide video (viewer hanya untuk gambar). `openImageViewer` hanya dari slide image; sesuaikan index viewer (viewer terima `safeImages` saja; petakan index slide→image dengan mengurangi 1 kalau ada video).
- Di IntersectionObserver active-tracker: saat slide aktif bukan slide video (index berubah dari 0), `videoElRef.current?.pause()` (pause saat swipe pergi). Tambah efek: `useEffect(() => { if (video && active !== 0) videoElRef.current?.pause(); }, [active, video]);`.
- Helper `formatClock(sec)` kecil (mm:ss) untuk badge durasi (durasi null → sembunyikan badge).

- [ ] **Step 2: Pass video dari halaman detail**

Di `app/products/[slug]/page.tsx`:
- Import: `import { productVideoMp4 } from "@/lib/product/product-video-url";`.
- Setelah `productImages` dibangun, hitung:
```tsx
  const detailVideoMp4 = productVideoMp4(product.videoUrl, 720);
  const detailVideo =
    detailVideoMp4 && product.videoThumbnailUrl
      ? {
          mp4Url: detailVideoMp4,
          thumbnailUrl: product.videoThumbnailUrl,
          durationSec: product.videoDurationSec ?? null,
        }
      : undefined;
```
- Di pemakaian `<ProductImageCarousel images={productImages} ... />`, tambah prop `video={detailVideo}`.

- [ ] **Step 3: tsc + eslint + test** — `npx tsc --noEmit` 0; eslint kedua file 0; `npm test` hijau.

- [ ] **Step 4: Commit**
```bash
git add components/ProductImageCarousel.tsx "app/products/[slug]/page.tsx"
git commit -m "feat(product-video-web): video slide #1 di galeri detail (manual play)"
```

---

## Task 5: Verifikasi akhir

- [ ] **Step 1: Gate menyeluruh**
`npx tsc --noEmit` 0-error · `npx eslint .` 0-error (warning pre-existing boleh) · `npm test` hijau (termasuk suite baru).

- [ ] **Step 2: Commit (kalau ada perubahan)** — bila semua bersih, tak ada commit tambahan.

> **SMOKE-TEST MANUAL (gate sebelum merge — sandbox tak bisa `next build` karena butuh DB):**
> Deploy branch → preview. Buka Katalog/Beranda: kartu produk yang punya video autoplay bisu saat terlihat, foto saat lainnya, tidak ada kotak hitam, scroll mulus. Buka detail produk itu: slide #1 = thumbnail + ▶, klik → main dengan suara+kontrol, swipe ke foto → pause. Cek di HP (mobile web) + desktop. Kalau MP4 tak ada (MP4 Fallback off) → kartu tetap tampil foto (tak rusak).

## Self-Review
- Grid Katalog+Beranda (satu `ProductCard`) → Task 3 ✓. Detail slide #1 → Task 4 ✓. MP4-not-HLS + fallback → Task 1 + komponen onError ✓. Visible-only + konkurensi → Task 2 ✓. Manual play detail → Task 4 ✓. Tanpa API/DB → benar (StoreProduct sudah punya field). ✓
- Placeholder: tidak ada. Type consistency: `productVideoMp4` signature sama di Task 1/3/4; `video` prop shape sama Task 4 carousel + page.
