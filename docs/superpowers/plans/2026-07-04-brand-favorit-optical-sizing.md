# Brand Favorit Optical Sizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix inconsistent logo sizing in the Home "Brand Favorit" grid, normalize brand logos on upload, and backfill existing logos — so every brand card reads at the same visual weight.

**Architecture:** Three independent layers. (A) Flutter render fix — patok tinggi logo dengan `ConstrainedBox`, longgarkan padding, sedikit naikkan aspect ratio kartu. (B) A shared `sharp`-based normalize module used by the admin upload route (opt-in per `kind=brand-logo`) so newly uploaded logos are trimmed and padded onto a uniform canvas. (C) A one-off Node script reusing the same module to backfill every existing `Brand.logoUrl`.

**Tech Stack:** Flutter/Dart (`flutter_test` golden tests), Next.js API route (TypeScript), `sharp` for image processing, Prisma + UploadThing for the backfill script, `node:test` for unit tests (matches existing `tests/*.test.ts` convention run via `tsx --test`).

## Global Constraints

- Foto produk (non-logo) upload path must not change — normalization is opt-in via an explicit `kind` field, defaulting to the old behavior.
- No DB schema changes — `Brand.logoUrl` stays a single string column ([schema.prisma:311](../../../prisma/schema.prisma)).
- No changes to Brand Favorit carousel/auto-slide logic ([home_screen.dart:3422-3517](../../../flutter_app/lib/screens/home_screen.dart)) — only the card/logo rendering.
- No changes to other Home sections.
- Backfill script must be resume-safe and must not delete the old logo before the new upload succeeds (matches pattern in [migrate-images-to-uploadthing.ts](../../../scripts/migrate-images-to-uploadthing.ts)).

---

### Task 1: Flutter — patok tinggi logo & longgarkan padding kartu

**Files:**
- Modify: `flutter_app/lib/screens/home_screen.dart:3525-3723` (`_BrandChoiceSectionState.build`, `_BrandGridCard`, `_BrandLogoImage`, `_BrandInitial` — rename the latter three to drop the leading underscore so a golden test in another file can import them)
- Test: `flutter_app/test/golden/brand_grid_card_test.dart` (new)

**Interfaces:**
- Produces: `BrandGridCard({required PetBrand brand, required VoidCallback onTap})`, `BrandLogoImage({required PetBrand brand})`, `BrandInitial({required PetBrand brand})` — all public widgets exported from `package:natalo_petshop_flutter/screens/home_screen.dart`. Consumed by `_BrandChoiceSectionState.build` (same file) and by the new golden test.
- Consumes: `PetBrand` from `flutter_app/lib/models/brand.dart` (already public — `name`, `color`, `imageAsset`, `logoUrl`, `slug`, `productCount`).

- [ ] **Step 1: Write the failing golden test**

Create `flutter_app/test/golden/brand_grid_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:natalo_petshop_flutter/screens/home_screen.dart';
import 'package:natalo_petshop_flutter/models/brand.dart';

/// Golden test untuk `BrandGridCard` — capture render side-by-side untuk
/// logo banner lebar (happy-cat) vs logo kotak (drontal) vs fallback
/// inisial. Fail di future runs kalau:
/// - Logo banner melar mepet tepi lagi (regresi ConstrainedBox height)
/// - Logo kotak balik tenggelam kecil di tengah
/// - Padding kartu berubah tanpa sengaja
///
/// Run:
/// ```bash
/// flutter test --update-goldens test/golden/brand_grid_card_test.dart
/// flutter test test/golden/brand_grid_card_test.dart
/// ```
void main() {
  testWidgets('BrandGridCard renders consistent optical size across logo shapes',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  height: 76,
                  child: BrandGridCard(
                    brand: PetBrand(
                      name: 'Happy Cat',
                      color: Color(0xFF1E5FBF),
                      imageAsset: 'assets/brands/happy-cat.png',
                    ),
                    onTap: null,
                  ),
                ),
                SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  height: 76,
                  child: BrandGridCard(
                    brand: PetBrand(
                      name: 'Drontal',
                      color: Color(0xFF1E5FBF),
                      imageAsset: 'assets/brands/drontal.png',
                    ),
                    onTap: null,
                  ),
                ),
                SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  height: 76,
                  child: BrandGridCard(
                    brand: PetBrand(
                      name: 'Tanpa Logo',
                      color: Color(0xFF1E5FBF),
                    ),
                    onTap: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('brand_grid_card_states.png'),
    );
  });
}
```

Note: `BrandGridCard.onTap` currently requires a non-null `VoidCallback`. Step 3 will widen it to `VoidCallback?` so this test (and any card with no interaction) compiles.

- [ ] **Step 2: Run test to verify it fails**

Run (from `flutter_app/`): `flutter test test/golden/brand_grid_card_test.dart`
Expected: FAIL — compile error (`BrandGridCard`, `BrandLogoImage`, `BrandInitial` are not defined; they're still private `_BrandGridCard` etc.), or a golden mismatch if the file already exists. Since the golden PNG doesn't exist yet, the very first successful run should be done with `--update-goldens` in Step 4 below — this step just confirms the current code doesn't compile against the new public names yet.

- [ ] **Step 3: Implement the render fix**

In `flutter_app/lib/screens/home_screen.dart`, replace lines 3525-3536 (inside `_BrandChoiceSectionState.build`) — the aspect ratio constant:

```dart
    // Compute card height dari aspect ratio + screen width
    // (childAspectRatio: 1.35 = width/height — sedikit lebih tinggi dari
    // sebelumnya (1.45) supaya logo kotak/tinggi punya ruang yang sama
    // dengan logo banner lebar; lihat _BrandLogoImage untuk patok tinggi).
    final screenWidth = MediaQuery.sizeOf(context).width;
    final innerWidth = screenWidth - 32; // 16 padding × 2
    final cardWidth = (innerWidth - 24) / 3; // 12 spacing × 2 between 3 cols
    final cardHeight = cardWidth / 1.35;
    final gridHeight = (cardHeight * 2) + 12; // 2 rows + mainAxisSpacing
```

Update the `childAspectRatio` in the `GridView.builder`'s delegate (around line 3584) from `1.45` to `1.35`:

```dart
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                    ),
```

Replace the whole `_BrandGridCard` class (lines 3605-3664) with a public `BrandGridCard`, wider horizontal padding, and a fixed-height wrapper for the logo:

```dart
/// Compact brand card untuk 2×3 grid carousel.
/// Pertahankan visual style Natalo (white bg, soft border, soft shadow).
class BrandGridCard extends StatelessWidget {
  final PetBrand brand;
  final VoidCallback? onTap;

  const BrandGridCard({super.key, required this.brand, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Patok tinggi logo ke garis yang sama untuk semua brand —
              // ini yang menghentikan logo banner lebar (Happy Dog, Royal
              // Canin) melar mepet tepi sementara logo kotak (Nexgard,
              // Whiskas) tenggelam kecil. BoxFit.contain di dalam
              // ConstrainedBox mengepaskan ke TINGGI yang sama, bukan ke
              // seluruh area kartu.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 26),
                child: BrandLogoImage(brand: brand),
              ),
              const SizedBox(height: 4),
              Text(
                brand.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Replace `_BrandLogoImage` (lines 3666-3703) with a public `BrandLogoImage`:

```dart
class BrandLogoImage extends StatelessWidget {
  final PetBrand brand;

  const BrandLogoImage({super.key, required this.brand});

  @override
  Widget build(BuildContext context) {
    // 1) Logo URL dari API → cached network image (PWA brand)
    final logoUrl = brand.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: logoUrl,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (context, url) => const Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => BrandInitial(brand: brand),
      );
    }
    // 2) Image asset lokal (sampleBrands fallback)
    final imageAsset = brand.imageAsset;
    if (imageAsset != null) {
      return Image.asset(
        imageAsset,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            BrandInitial(brand: brand),
      );
    }
    // 3) Fallback: inisial huruf
    return BrandInitial(brand: brand);
  }
}
```

Replace `_BrandInitial` (lines 3705-3723) with a public `BrandInitial`:

```dart
class BrandInitial extends StatelessWidget {
  final PetBrand brand;

  const BrandInitial({super.key, required this.brand});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        brand.name.isEmpty ? '?' : brand.name[0],
        style: TextStyle(
          color: brand.color,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
```

Update the single call site in `_BrandChoiceSectionState.build` (around line 3589) from `_BrandGridCard(...)` to `BrandGridCard(...)` (same named arguments — no other change needed).

- [ ] **Step 4: Generate the golden image and run the test**

Run (from `flutter_app/`): `flutter test --update-goldens test/golden/brand_grid_card_test.dart`
Expected: PASS, and `flutter_app/test/golden/brand_grid_card_states.png` is created.

Run again without `--update-goldens` to confirm it's stable: `flutter test test/golden/brand_grid_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Manual visual check on the real Home screen**

Run the app (`flutter run`) or use the existing dev workflow, navigate to Home, and confirm in the "Brand Favorit" grid that wide logos (Happy Dog, Happy Cat, Royal Canin) no longer look larger than boxy logos (Nexgard, Whiskas, Hill's) — all should sit within the same ~26px height band with visible padding around them.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/home_screen.dart flutter_app/test/golden/brand_grid_card_test.dart flutter_app/test/golden/brand_grid_card_states.png
git commit -m "fix(home): patok tinggi logo Brand Favorit biar optical sizing seragam"
```

---

### Task 2: Web — shared logo normalization module

**Files:**
- Create: `lib/upload/normalize-logo.ts`
- Test: `tests/normalize-logo.test.ts`

**Interfaces:**
- Produces: `normalizeBrandLogo(input: Buffer): Promise<Buffer>` — takes any raster image buffer (PNG/JPEG/WEBP/GIF), returns a PNG buffer: trimmed of transparent/solid-color border, then composited onto a square transparent canvas with the logo occupying ~80% of the canvas. Consumed by Task 3 (upload route) and Task 4 (backfill script).
- Consumes: `sharp` (already a dependency, [package.json:86](../../../package.json)).

- [ ] **Step 1: Write the failing test**

Create `tests/normalize-logo.test.ts`:

```typescript
import assert from "node:assert/strict";
import test from "node:test";
import sharp from "sharp";
import { normalizeBrandLogo } from "@/lib/upload/normalize-logo";

async function makePngBuffer(options: {
  width: number;
  height: number;
  contentWidth: number;
  contentHeight: number;
}): Promise<Buffer> {
  const { width, height, contentWidth, contentHeight } = options;
  const left = Math.round((width - contentWidth) / 2);
  const top = Math.round((height - contentHeight) / 2);

  const canvas = sharp({
    create: {
      width,
      height,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  });

  const content = await sharp({
    create: {
      width: contentWidth,
      height: contentHeight,
      channels: 4,
      background: { r: 200, g: 30, b: 30, alpha: 255 },
    },
  })
    .png()
    .toBuffer();

  return canvas
    .composite([{ input: content, left, top }])
    .png()
    .toBuffer();
}

test("normalizeBrandLogo produces a square canvas regardless of input aspect ratio", async () => {
  const wideBanner = await makePngBuffer({
    width: 400,
    height: 400,
    contentWidth: 380,
    contentHeight: 60,
  });

  const output = await normalizeBrandLogo(wideBanner);
  const meta = await sharp(output).metadata();

  assert.equal(meta.width, meta.height, "output canvas must be square");
});

test("normalizeBrandLogo trims transparent padding before re-padding", async () => {
  const tinyContentOnBigCanvas = await makePngBuffer({
    width: 500,
    height: 500,
    contentWidth: 50,
    contentHeight: 50,
  });

  const output = await normalizeBrandLogo(tinyContentOnBigCanvas);
  const stats = await sharp(output).clone().extractChannel(3).stats();

  // Setelah trim + re-pad ke ~80% kanvas, opaque pixel harus jauh lebih
  // dominan dibanding versi asli (yang isinya 50x50 di kanvas 500x500 —
  // opaque ratio sangat kecil).
  const opaqueRatio = stats.channels[0].mean / 255;
  assert.ok(
    opaqueRatio > 0.4,
    `expected re-padded logo to fill most of the canvas, got opaque ratio ${opaqueRatio}`,
  );
});

test("normalizeBrandLogo returns a decodable PNG buffer", async () => {
  const input = await makePngBuffer({
    width: 300,
    height: 150,
    contentWidth: 280,
    contentHeight: 40,
  });

  const output = await normalizeBrandLogo(input);
  const meta = await sharp(output).metadata();

  assert.equal(meta.format, "png");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx --test tests/normalize-logo.test.ts`
Expected: FAIL with a module-not-found error for `@/lib/upload/normalize-logo`.

- [ ] **Step 3: Implement `normalizeBrandLogo`**

Create `lib/upload/normalize-logo.ts`:

```typescript
/**
 * Normalisasi logo brand sebelum disimpan — supaya semua logo punya berat
 * visual yang sama di grid "Brand Favorit" (Home), lepas dari aspect ratio
 * atau padding transparan bawaan file aslinya.
 *
 * Pipeline:
 *   1. Trim border transparan/solid di tepi gambar.
 *   2. Composite logo yang sudah di-trim ke tengah kanvas persegi
 *      transparan, mengisi ~80% kanvas (LOGO_FILL_RATIO).
 *
 * Dipakai bersama oleh:
 * - app/api/admin/upload/route.ts (upload logo baru, kind=brand-logo)
 * - scripts/normalize-brand-logos.mjs (backfill logo lama)
 */
import sharp from "sharp";

const CANVAS_SIZE = 512;
const LOGO_FILL_RATIO = 0.8;

export async function normalizeBrandLogo(input: Buffer): Promise<Buffer> {
  const trimmed = await sharp(input).trim().png().toBuffer();
  const trimmedMeta = await sharp(trimmed).metadata();

  const maxLogoDimension = Math.round(CANVAS_SIZE * LOGO_FILL_RATIO);
  const resized = await sharp(trimmed)
    .resize({
      width: maxLogoDimension,
      height: maxLogoDimension,
      fit: "inside",
      withoutEnlargement:
        (trimmedMeta.width ?? 0) >= maxLogoDimension ||
        (trimmedMeta.height ?? 0) >= maxLogoDimension,
    })
    .png()
    .toBuffer();
  const resizedMeta = await sharp(resized).metadata();

  const resizedWidth = resizedMeta.width ?? maxLogoDimension;
  const resizedHeight = resizedMeta.height ?? maxLogoDimension;
  const left = Math.round((CANVAS_SIZE - resizedWidth) / 2);
  const top = Math.round((CANVAS_SIZE - resizedHeight) / 2);

  return sharp({
    create: {
      width: CANVAS_SIZE,
      height: CANVAS_SIZE,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([{ input: resized, left, top }])
    .png()
    .toBuffer();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx tsx --test tests/normalize-logo.test.ts`
Expected: PASS (3/3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/upload/normalize-logo.ts tests/normalize-logo.test.ts
git commit -m "feat(upload): tambah normalizeBrandLogo — trim + pad logo ke kanvas seragam"
```

---

### Task 3: Web — wire normalization into the upload route (opt-in, brand-logo only)

**Files:**
- Modify: `app/api/admin/upload/route.ts`
- Modify: `components/admin/BrandLogoUploadButton.tsx`
- Test: `tests/upload-route-kind.test.ts` (new — tests the branching logic in isolation, not the full Next.js route handler, matching the existing `tests/*.test.ts` unit-test style)

**Interfaces:**
- Produces: `resolveUploadKind(rawKind: FormDataEntryValue | null): "product" | "brand-logo"` — small pure helper extracted so the branching logic (which decides whether to normalize) is unit-testable without spinning up a Next.js request. Exported from `app/api/admin/upload/route.ts`.
- Consumes: `normalizeBrandLogo` from Task 2 (`@/lib/upload/normalize-logo`), `uploadToUT` from `lib/uploadthing.ts` (existing, unchanged signature `uploadToUT(file: File, prefix?: string): Promise<UploadResult>`).

- [ ] **Step 1: Write the failing test**

Create `tests/upload-route-kind.test.ts`:

```typescript
import assert from "node:assert/strict";
import test from "node:test";
import { resolveUploadKind } from "@/app/api/admin/upload/route";

test("resolveUploadKind defaults to product when kind is missing", () => {
  assert.equal(resolveUploadKind(null), "product");
});

test("resolveUploadKind defaults to product for unknown values", () => {
  assert.equal(resolveUploadKind("banner" as unknown as FormDataEntryValue), "product");
});

test("resolveUploadKind recognizes brand-logo", () => {
  assert.equal(resolveUploadKind("brand-logo" as unknown as FormDataEntryValue), "brand-logo");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx --test tests/upload-route-kind.test.ts`
Expected: FAIL — `resolveUploadKind` is not exported from the route module yet.

- [ ] **Step 3: Implement the route change**

Replace the contents of `app/api/admin/upload/route.ts`:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";
import { normalizeBrandLogo } from "@/lib/upload/normalize-logo";
import { uploadToUT } from "@/lib/uploadthing";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const MAX_SIZE = 2 * 1024 * 1024;

export type UploadKind = "product" | "brand-logo";

export function resolveUploadKind(rawKind: FormDataEntryValue | null): UploadKind {
  return rawKind === "brand-logo" ? "brand-logo" : "product";
}

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;
  const kind = resolveUploadKind(formData.get("kind"));

  if (!file) {
    return NextResponse.json({ error: "File tidak ditemukan" }, { status: 400 });
  }

  if (!ALLOWED_TYPES.has(file.type)) {
    return NextResponse.json(
      { error: "Format harus JPG, PNG, WEBP, atau GIF" },
      { status: 400 }
    );
  }

  if (file.size > MAX_SIZE) {
    return NextResponse.json({ error: "Ukuran file maksimal 2 MB" }, { status: 400 });
  }

  const buffer = Buffer.from(await file.arrayBuffer());
  if (!validateImageMagicBytes(buffer, file.type)) {
    return NextResponse.json(
      { error: "Isi file tidak cocok dengan format gambar" },
      { status: 415 }
    );
  }

  try {
    const uploadFile =
      kind === "brand-logo"
        ? new File([await normalizeBrandLogo(buffer)], file.name.replace(/\.\w+$/, ".png"), {
            type: "image/png",
          })
        : file;
    const { url } = await uploadToUT(uploadFile, kind === "brand-logo" ? "brand-logo" : "product");
    return NextResponse.json({ url });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "Upload gagal" },
      { status: 500 }
    );
  }
}
```

In `components/admin/BrandLogoUploadButton.tsx`, add the `kind` field to the outgoing `FormData` (in the `upload` function):

```typescript
    setUploading(true);
    const formData = new FormData();
    formData.append("file", file);
    formData.append("kind", "brand-logo");
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx tsx --test tests/upload-route-kind.test.ts`
Expected: PASS (3/3 tests).

- [ ] **Step 5: Run the full test suite to confirm no regression on product uploads**

Run: `npm test`
Expected: All existing tests still PASS (product upload path is unchanged — `kind` defaults to `"product"`, which skips `normalizeBrandLogo` entirely).

- [ ] **Step 6: Manual check in the admin UI**

Start the admin dev server, open the brand logo upload control, upload a logo with heavy transparent padding (e.g. one of the existing `assets/brands/*.png` files re-saved), and confirm the resulting `logoUrl` image (visible in the button preview) fills its frame consistently rather than floating small in the middle.

- [ ] **Step 7: Commit**

```bash
git add app/api/admin/upload/route.ts components/admin/BrandLogoUploadButton.tsx tests/upload-route-kind.test.ts
git commit -m "feat(admin): normalisasi logo brand saat upload (kind=brand-logo), foto produk tidak berubah"
```

---

### Task 4: One-off backfill script for existing brand logos

**Files:**
- Create: `scripts/normalize-brand-logos.mjs`

**Interfaces:**
- Consumes: `normalizeBrandLogo` from `lib/upload/normalize-logo.ts` (Task 2) — imported via `tsx`'s on-the-fly TS support since this script runs with `npx tsx`, matching how `.ts`-importing `.mjs`/`.ts` scripts already work in this repo (e.g. `scripts/migrate-images-to-uploadthing.ts` imports `@prisma/client` directly). This script will be a `.mjs` file that imports the compiled logic by re-implementing the tiny wrapper inline is unnecessary — instead it imports directly from the TS source path using `tsx`'s loader, so run it as `npx tsx scripts/normalize-brand-logos.mjs`.
- Consumes: `PrismaClient` (`@prisma/client`), `UTApi` (`uploadthing/server`) — same imports as `scripts/migrate-images-to-uploadthing.ts`.

- [ ] **Step 1: Write the script**

Create `scripts/normalize-brand-logos.mjs`:

```javascript
/**
 * Backfill: normalisasi semua logo Brand yang sudah ada di DB — trim
 * padding transparan + pad ulang ke kanvas seragam (lihat
 * lib/upload/normalize-logo.ts), lalu re-upload ke UploadThing dan update
 * Brand.logoUrl.
 *
 * Usage: npx tsx scripts/normalize-brand-logos.mjs
 *
 * Resume-safe: aman dijalankan berkali-kali — brand yang gagal di run
 * sebelumnya cukup dijalankan ulang, brand yang sudah sukses akan
 * dinormalisasi ulang lagi (idempoten secara visual, hanya boros 1 upload
 * ekstra kalau di-rerun tanpa alasan).
 * Pakai DATABASE_URL dan UPLOADTHING_TOKEN dari .env (= production).
 */
import { PrismaClient } from "@prisma/client";
import { UTApi } from "uploadthing/server";
import { normalizeBrandLogo } from "../lib/upload/normalize-logo.ts";

const prisma = new PrismaClient();
const utapi = new UTApi();

const BATCH = 4; // sharp CPU-bound — jangan terlalu paralel

async function processOne(brand) {
  const response = await fetch(brand.logoUrl);
  if (!response.ok) {
    throw new Error(`fetch failed: HTTP ${response.status}`);
  }
  const inputBuffer = Buffer.from(await response.arrayBuffer());
  const normalizedBuffer = await normalizeBrandLogo(inputBuffer);

  const filename = `brand-logo-${brand.slug}-${Date.now()}.png`;
  const file = new File([normalizedBuffer], filename, { type: "image/png" });
  const res = await utapi.uploadFiles(file);
  if (res.error || !res.data) {
    throw new Error(res.error?.message ?? "upload gagal");
  }

  await prisma.brand.update({
    where: { id: brand.id },
    data: { logoUrl: res.data.ufsUrl },
  });
}

async function main() {
  console.log("=== Normalisasi Brand.logoUrl (trim + pad seragam) ===\n");

  const brands = await prisma.brand.findMany({
    where: { logoUrl: { not: null } },
    select: { id: true, slug: true, name: true, logoUrl: true },
  });

  console.log(`Total brand dengan logo: ${brands.length}\n`);

  let done = 0;
  let failed = 0;
  const failures = [];
  const startTime = Date.now();

  for (let i = 0; i < brands.length; i += BATCH) {
    const batch = brands.slice(i, i + BATCH);
    await Promise.all(
      batch.map(async (brand) => {
        try {
          await processOne(brand);
          done++;
        } catch (e) {
          failed++;
          failures.push(`${brand.slug}: ${e.message}`);
        }
      }),
    );
    const elapsed = (Date.now() - startTime) / 1000;
    process.stdout.write(
      `\r[${done + failed}/${brands.length}] ok=${done} fail=${failed} elapsed=${Math.round(elapsed)}s`,
    );
  }

  console.log(`\n\n=== Selesai ===`);
  console.log(`Sukses: ${done}`);
  console.log(`Gagal: ${failed}`);
  if (failures.length > 0) {
    console.log(`\nDetail gagal:`);
    failures.forEach((f) => console.log(`  - ${f}`));
  }
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
```

- [ ] **Step 2: Dry-run sanity check against a single brand**

Before running against the full table, verify the pipeline end-to-end against one row. Run: `npx tsx -e "
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
const b = await prisma.brand.findFirst({ where: { logoUrl: { not: null } } });
console.log(b?.slug, b?.logoUrl);
await prisma.\$disconnect();
"`
Expected: prints a real `slug` and `logoUrl` — confirms `DATABASE_URL` in `.env` is reachable before running the full backfill.

- [ ] **Step 3: Run the backfill**

Run: `npx tsx scripts/normalize-brand-logos.mjs`
Expected: Progress line updates per batch, ends with `Sukses: N` matching (or close to) the total brand count printed at the start. Any `Gagal` entries are printed with the reason — re-run the script to retry those (fetch failures are usually transient).

- [ ] **Step 4: Spot-check the result**

Open the admin `/admin/brands` page (or the customer Home "Brand Favorit" section) and confirm 3-4 previously-inconsistent logos (e.g. Happy Dog, Nexgard, Royal Canin, Whiskas) now render at a consistent visual size.

- [ ] **Step 5: Commit**

```bash
git add scripts/normalize-brand-logos.mjs
git commit -m "chore(scripts): backfill normalisasi Brand.logoUrl yang sudah ada"
```
