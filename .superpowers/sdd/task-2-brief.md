# Task 2: Normalize create and edit payloads at one API boundary

Work only in `C:/Users/USER/Desktop/natalopetshopflutter/.worktrees/unified-admin-product-form`.

Modify `app/api/admin/products/route.ts`, `app/api/admin/products/[id]/route.ts`, and `lib/product/admin-product-form.ts`. Add/extend `tests/admin-product-form.test.ts`.

Create a shared `ProductFormPayload`/normalizer that accepts name, description, `imageUrls` (1–9), categoryId, brandId, price, stock, weightGram, sku, variant draft payload, and optional video metadata. It must reject no-photo payloads with `Minimal satu foto wajib diisi`, map index 0 to imageUrl and the remainder to max-8 gallery entries, and preserve current nested variant Zod issues. Create with a selected video must use the hidden lifecycle from Task 1 (`creationState=creating`, `isActive=false`) and respond with `{ id, creationState, requiresVideoFinalize }`. Create without video can finalize immediately.

Move current edit server-action behavior into the shared transaction service: gallery, category, brand, SKU, variants, and `lastEditedAt` must update together. Keep existing stock/price/weight rules: variant products derive aggregates; single products require valid price/stock/weight. Keep authorization and search sync behavior.

Use TDD: first add tests for video-aware hidden creation and no-photo rejection, run `npx vitest run tests/admin-product-form.test.ts` expecting failure, implement, then run `npx vitest run tests/admin-product-form.test.ts tests/product-video-serialize.test.ts` and ensure pass. Self-review and commit `feat(products): unify product form API contracts`. Write `.superpowers/sdd/task-2-report.md` with status, commit hash, tests/output, and concerns.

Global constraints: preserve Natalo styling and unrelated code; do not expose creating products; do not change public UI.
