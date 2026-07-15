# Unified Admin Product Form Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver one complete admin product form for create and edit, including compact media rails, draft-safe video handling, AI description, variants, and direct return to the product list.

**Architecture:** Server-side product-form services own validation, transactions, creation visibility, and compensation. A client `ProductForm` owns one draft state in both modes and composes focused media, video, variant, and AI-description components.

**Tech Stack:** Next.js App Router, React, TypeScript, Prisma/PostgreSQL, Zod, Bunny Stream TUS, Vitest.

## Global Constraints

- Retain current Natalo admin colors, typography, spacing, and existing admin UI primitives.
- Enforce 1–9 photos: index zero is the cover and the other eight are gallery images.
- Video stays optional and retains existing file/type/trim limits.
- `creating` products are invisible in admin and public product reads.
- Existing media is only deleted after successful Save; Batal has no persistence effect.
- Both modes return to `/admin/products` only after success.

---

## Task 1: Add Product creation lifecycle and service

**Files:**
- Modify: `prisma/schema.prisma:374-438`
- Create: `prisma/migrations/<timestamp>_add_product_creation_state/migration.sql`
- Create: `lib/product/admin-product-form.ts`
- Test: `tests/admin-product-form.test.ts`

**Interfaces:**
- Produces `type ProductCreationState = "creating" | "ready"`.
- Produces `productIsVisibleWhere()`, `createHiddenProduct(payload)`, `finalizeCreatedProduct(id)`, and `compensateCreatedProduct(id)`.

- [ ] **Step 1: Write the failing lifecycle tests**

```ts
import { describe, expect, it } from "vitest";
import {
  productIsVisibleWhere,
  shouldDeleteCreatingProduct,
} from "@/lib/product/admin-product-form";

describe("admin product creation lifecycle", () => {
  it("excludes creating products from visible reads", () => {
    expect(productIsVisibleWhere()).toEqual({ creationState: "ready" });
  });

  it("only compensates an unfinished product", () => {
    expect(shouldDeleteCreatingProduct("creating")).toBe(true);
    expect(shouldDeleteCreatingProduct("ready")).toBe(false);
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npx vitest run tests/admin-product-form.test.ts`

Expected: FAIL because `admin-product-form` does not exist.

- [ ] **Step 3: Add the migration and minimal service**

```prisma
model Product {
  // existing fields
  creationState String @default("ready")
  // existing fields
  @@index([creationState, isActive])
}
```

```sql
ALTER TABLE "Product" ADD COLUMN "creationState" TEXT NOT NULL DEFAULT 'ready';
CREATE INDEX "Product_creationState_is_active_idx"
  ON "Product" ("creationState", "is_active");
```

```ts
export type ProductCreationState = "creating" | "ready";

export function productIsVisibleWhere() {
  return { creationState: "ready" as const };
}

export function shouldDeleteCreatingProduct(state: ProductCreationState) {
  return state === "creating";
}
```

Implement `createHiddenProduct` by reusing the current product-plus-variants transaction with `creationState: "creating"` and `isActive: false`. `finalizeCreatedProduct` sets `creationState: "ready"`, restores the existing stock-derived active value, and schedules search sync. `compensateCreatedProduct` can delete only a `creating` record and its Bunny asset.

- [ ] **Step 4: Generate Prisma client and run test**

Run: `npx prisma generate && npx vitest run tests/admin-product-form.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add prisma/schema.prisma prisma/migrations lib/product/admin-product-form.ts tests/admin-product-form.test.ts
git commit -m "feat(products): add hidden creation lifecycle"
```

## Task 2: Normalize create and edit payloads at one API boundary

**Files:**
- Modify: `app/api/admin/products/route.ts`
- Modify: `app/api/admin/products/[id]/route.ts`
- Modify: `lib/product/admin-product-form.ts`
- Test: `tests/admin-product-form.test.ts`

**Interfaces:**
- Produces `normalizeProductFormPayload(raw)` and `updateProductFromForm(id, payload)`.
- `POST /api/admin/products` returns `{ id, creationState, requiresVideoFinalize }`.

- [ ] **Step 1: Write the failing payload tests**

```ts
it("creates a hidden record when video is selected", () => {
  const result = normalizeProductFormPayload({
    name: "Snack", description: "Aman", imageUrls: ["https://img/1"],
    price: 10000, stock: 1, weightGram: 100, video: { durationSec: 12 },
  });
  expect(result.creationState).toBe("creating");
  expect(result.isActive).toBe(false);
});

it("rejects a form without photos", () => {
  expect(() => normalizeProductFormPayload(validPayload({ imageUrls: [] })))
    .toThrow("Minimal satu foto wajib diisi");
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npx vitest run tests/admin-product-form.test.ts`

Expected: FAIL because `normalizeProductFormPayload` is absent.

- [ ] **Step 3: Implement one normalizer and transaction-based update**

```ts
export type ProductFormPayload = {
  name: string; description: string; imageUrls: string[];
  categoryId?: string | null; brandId?: string | null;
  price: number; stock: number; weightGram: number; sku?: string | null;
  variants: VariantEditorDraftPayload;
  video?: { durationSec: number } | null;
};

export function normalizeProductFormPayload(raw: unknown): NormalizedProductFormPayload;
export async function updateProductFromForm(
  id: string,
  payload: NormalizedProductFormPayload,
): Promise<Product>;
```

Use `imageUrls[0]` as `imageUrl` and the rest as gallery. Reuse the current nested variant Zod error shape. Move the current edit server-action fields—gallery, category, brand, SKU, variants, and `lastEditedAt`—to this one transaction service.

- [ ] **Step 4: Verify**

Run: `npx vitest run tests/admin-product-form.test.ts tests/product-video-serialize.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add app/api/admin/products/route.ts app/api/admin/products/[id]/route.ts lib/product/admin-product-form.ts tests/admin-product-form.test.ts
git commit -m "feat(products): unify product form API contracts"
```

## Task 3: Add draft-safe video state and compensation

**Files:**
- Create: `components/admin/ProductVideoDraft.tsx`
- Modify: `components/admin/ProductVideoUpload.tsx`
- Modify: `app/api/admin/products/[id]/video/route.ts`
- Test: `tests/admin-product-form.test.ts`
- Test: `tests/product-video-serialize.test.ts`

**Interfaces:**
- Produces `ProductVideoDraftHandle` with `prepareForSave()`, `commitAfterProductSave(productId)`, and `discardPendingCreation()`.
- Consumes existing `readVideoMetadata`, `trimVideo`, `uploadToBunnyViaTus`, and Bunny product-video route.

- [ ] **Step 1: Write the failing video mutation tests**

```ts
it("keeps an existing video when save has not succeeded", () => {
  expect(nextVideoMutation({ existingGuid: "old", removeRequested: true, saveSucceeded: false }))
    .toEqual({ deleteGuid: null, preserveGuid: "old" });
});

it("compensates a hidden create when upload fails", () => {
  expect(nextVideoMutation({ creatingProductId: "p1", uploadFailed: true }))
    .toEqual({ compensateProductId: "p1" });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npx vitest run tests/admin-product-form.test.ts tests/product-video-serialize.test.ts`

Expected: FAIL because `nextVideoMutation` is absent.

- [ ] **Step 3: Implement deterministic video decisions and component**

```ts
export function nextVideoMutation(input: VideoMutationInput): VideoMutationResult {
  if (input.uploadFailed && input.creatingProductId) {
    return { compensateProductId: input.creatingProductId };
  }
  if (!input.saveSucceeded) {
    return { deleteGuid: null, preserveGuid: input.existingGuid ?? null };
  }
  return input.removeRequested
    ? { deleteGuid: input.existingGuid ?? null, preserveGuid: null }
    : { deleteGuid: null, preserveGuid: input.existingGuid ?? null };
}
```

Move the picker, metadata, trim controls, and TUS progress into `ProductVideoDraft`. Existing-video remove and replacement remain only draft intent. On edit replacement failure keep old database fields. On create failure/cancel call server compensation for the hidden product.

- [ ] **Step 4: Verify**

Run: `npx vitest run tests/admin-product-form.test.ts tests/product-video-serialize.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add components/admin/ProductVideoDraft.tsx components/admin/ProductVideoUpload.tsx app/api/admin/products/[id]/video/route.ts tests/admin-product-form.test.ts tests/product-video-serialize.test.ts
git commit -m "feat(products): defer video changes until save"
```

## Task 4: Build the compact media rail

**Files:**
- Create: `components/admin/ProductMediaRail.tsx`
- Modify: `components/MultiImageUpload.tsx`
- Test: `tests/admin-product-media.test.ts`

**Interfaces:**
- Produces `ProductMediaRail({ images, video, onImagesChange, onVideoIntentChange })`.
- Exports `removeImageAt(images, index)` and `canRemoveImage(images)` for focused tests.

- [ ] **Step 1: Write failing media tests**

```ts
import { canRemoveImage, removeImageAt } from "@/components/admin/ProductMediaRail";

it("promotes the next photo when cover is removed", () => {
  expect(removeImageAt(["cover", "second", "third"], 0)).toEqual(["second", "third"]);
});

it("blocks removal of final photo", () => {
  expect(canRemoveImage(["only"])).toBe(false);
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npx vitest run tests/admin-product-media.test.ts`

Expected: FAIL because `ProductMediaRail` does not exist.

- [ ] **Step 3: Implement rail behavior**

```tsx
export function ProductMediaRail(props: {
  images: string[];
  video: ProductVideoDraftValue;
  onImagesChange(images: string[]): void;
  onVideoIntentChange(intent: ProductVideoIntent): void;
}) {
  // compact thumbnail buttons, cover label, add tiles, preview dialog, and × controls
}
```

Use compact thumbnail tiles only. Stop propagation on each `×` control so it cannot open preview. The first photo gets the Cover marker; the add-photo slot disappears at nine images. Provide labels including `Hapus foto cover`, `Preview foto 2`, and `Hapus video`.

- [ ] **Step 4: Verify**

Run: `npx vitest run tests/admin-product-media.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add components/admin/ProductMediaRail.tsx components/MultiImageUpload.tsx tests/admin-product-media.test.ts
git commit -m "feat(admin): add compact product media rail"
```

## Task 5: Make AI description and variants controlled

**Files:**
- Modify: `components/admin/AiDescriptionField.tsx`
- Modify: `components/admin/VariantEditor.tsx`
- Create: `app/api/admin/products/generate-description/route.ts`
- Test: `tests/admin-product-form.test.ts`

**Interfaces:**
- `AiDescriptionField({ value, onChange, context, existingProductId? })`.
- `VariantEditor({ value, onChange, mode })`, where mode is `"controlled" | "standalone"`.

- [ ] **Step 1: Write failing controlled-state tests**

```ts
it("builds AI context for a new product without an ID", () => {
  expect(buildDescriptionContext({
    name: "Pakan", categoryName: "Kucing", brandName: "Natalo", variants: emptyVariants,
  })).toMatchObject({ name: "Pakan", categoryName: "Kucing" });
});

it("prevents a controlled VariantEditor from self-saving", () => {
  expect(variantPersistenceMode("controlled")).toBe("parent-save");
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npx vitest run tests/admin-product-form.test.ts`

Expected: FAIL because draft-context helpers do not exist.

- [ ] **Step 3: Implement controlled contracts**

```ts
export function buildDescriptionContext(context: ProductDescriptionContext) {
  return context;
}
export function variantPersistenceMode(mode: "controlled" | "standalone") {
  return mode === "controlled" ? "parent-save" : "self-save";
}
```

The create AI route accepts current name/category/brand/variants and never persists. Retain overwrite confirmation. In controlled mode VariantEditor emits draft changes only; all variant persistence occurs inside the parent product-form save transaction.

- [ ] **Step 4: Verify**

Run: `npx vitest run tests/admin-product-form.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add components/admin/AiDescriptionField.tsx components/admin/VariantEditor.tsx app/api/admin/products/generate-description/route.ts tests/admin-product-form.test.ts
git commit -m "feat(admin): control product variants and AI draft"
```

## Task 6: Assemble one ProductForm and route create/edit through it

**Files:**
- Create: `components/admin/ProductForm.tsx`
- Modify: `components/admin/NewProductForm.tsx`
- Modify: `app/admin/(protected)/products/new/page.tsx`
- Modify: `app/admin/(protected)/products/[id]/edit/page.tsx`
- Test: `tests/admin-product-form.test.ts`

**Interfaces:**
- Produces `ProductForm({ mode, categories, brands, initialProduct? })`.
- Exports `productFormCopy(mode)`.

- [ ] **Step 1: Write failing mode tests**

```ts
it("uses create wording and destination", () => {
  expect(productFormCopy("create")).toEqual({
    title: "Tambah Produk", submit: "Simpan Produk", successPath: "/admin/products",
  });
});

it("uses edit wording and destination", () => {
  expect(productFormCopy("edit")).toEqual({
    title: "Edit Produk", submit: "Simpan Perubahan", successPath: "/admin/products",
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npx vitest run tests/admin-product-form.test.ts`

Expected: FAIL because `productFormCopy` is absent.

- [ ] **Step 3: Implement shared form**

```tsx
export function ProductForm({ mode, categories, brands, initialProduct }: ProductFormProps) {
  const [draft, setDraft] = useState(() => makeProductFormDraft(mode, initialProduct));
  async function save() {
    // validate → POST/PATCH → video finalize → router.push("/admin/products")
  }
  return <AdminPage maxWidth="xl">{/* existing 3 sections and sticky actions */}</AdminPage>;
}

export function productFormCopy(mode: "create" | "edit") {
  return mode === "create"
    ? { title: "Tambah Produk", submit: "Simpan Produk", successPath: "/admin/products" }
    : { title: "Edit Produk", submit: "Simpan Perubahan", successPath: "/admin/products" };
}
```

Remove the create-only video placeholder and the `?from=new#video` redirect. Make the edit page a data loader that passes the full initial draft to ProductForm. Preserve current section navigation, `SectionCard`, and sticky bar layout.

- [ ] **Step 4: Verify**

Run: `npx tsc --noEmit && npx vitest run tests/admin-product-form.test.ts tests/admin-product-media.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add components/admin/ProductForm.tsx components/admin/NewProductForm.tsx app/admin/(protected)/products/new/page.tsx app/admin/(protected)/products/[id]/edit/page.tsx tests/admin-product-form.test.ts
git commit -m "feat(admin): unify create and edit product forms"
```

## Task 7: Hide stale creations and verify end-to-end behavior

**Files:**
- Modify: `app/admin/(protected)/products/page.tsx`
- Modify: product list/read helpers identified with `rg "isActive: true" app lib`
- Create: `app/api/admin/products/creating/cleanup/route.ts`
- Modify: `vercel.json` only if this repository already owns maintenance cron configuration.
- Test: `tests/admin-product-visibility.test.ts`

**Interfaces:**
- Consumes `productIsVisibleWhere()` and `compensateCreatedProduct(id)`.
- Produces `POST /api/admin/products/creating/cleanup`, authenticated by `CRON_SECRET`.

- [ ] **Step 1: Write failing visibility tests**

```ts
it("adds ready state to admin visibility", () => {
  expect(mergeProductVisibility({ isActive: true }))
    .toMatchObject({ isActive: true, creationState: "ready" });
});

it("selects only expired creating records for cleanup", () => {
  expect(cleanupWhere(new Date())).toMatchObject({
    creationState: "creating", createdAt: { lt: expect.any(Date) },
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npx vitest run tests/admin-product-visibility.test.ts`

Expected: FAIL because visibility helpers do not exist.

- [ ] **Step 3: Implement filters and cleanup**

```ts
export function mergeProductVisibility(where: Prisma.ProductWhereInput): Prisma.ProductWhereInput {
  return { ...where, creationState: "ready" };
}

export function cleanupWhere(now: Date): Prisma.ProductWhereInput {
  return {
    creationState: "creating",
    createdAt: { lt: new Date(now.getTime() - 60 * 60 * 1000) },
  };
}
```

Apply `mergeProductVisibility` to admin product list and all public product reads that must not expose hidden creations. Cleanup requires `Authorization: Bearer ${CRON_SECRET}`, compensates each selected record, and returns `{ cleaned: number }`.

- [ ] **Step 4: Run full checks**

Run: `npx tsc --noEmit && npm run lint && npx vitest run tests/admin-product-form.test.ts tests/admin-product-media.test.ts tests/admin-product-visibility.test.ts tests/product-video-serialize.test.ts tests/product-video-gc.test.ts tests/search.test.ts`

Expected: all commands exit 0.

- [ ] **Step 5: Manual QA and final commit**

Verify create photo-only, create with video, failed/cancelled upload, edit cancel, video replacement failure, cover promotion, nine-photo limit, and AI description in both modes. Then commit:

```powershell
git add app/admin/(protected)/products/page.tsx app/api/admin/products/creating/cleanup/route.ts lib/product/admin-product-form.ts tests/admin-product-visibility.test.ts vercel.json
git commit -m "feat(products): hide and clean unfinished creations"
```

