# Task 1: Add Product creation lifecycle and service

Modify `prisma/schema.prisma` Product with `creationState String @default("ready")` and index `[creationState, isActive]`. Add a migration that creates the non-null column defaulting all existing rows to `ready` and adds the index.

Create `lib/product/admin-product-form.ts` exporting:

```ts
export type ProductCreationState = "creating" | "ready";
export function productIsVisibleWhere(): { creationState: "ready" };
export function shouldDeleteCreatingProduct(state: ProductCreationState): boolean;
```

Also implement server helpers `createHiddenProduct(payload)`, `finalizeCreatedProduct(id)`, and `compensateCreatedProduct(id)`. Reuse the current product-plus-variants transaction; hidden records use `creationState: "creating"` and `isActive: false`. Finalization sets `creationState: "ready"` and existing stock-derived active state. Compensation deletes only a creating record and any Bunny asset.

Add `tests/admin-product-form.test.ts` with tests that `productIsVisibleWhere()` returns `{ creationState: "ready" }` and `shouldDeleteCreatingProduct("creating")` is true while `ready` is false.

Run `npx prisma generate && npx vitest run tests/admin-product-form.test.ts`. Self-review and commit with `feat(products): add hidden creation lifecycle`.

Global constraints: preserve existing admin behavior; never expose `creating` products in admin/public reads; do not touch unrelated dirty files in the main worktree. Work in `C:/Users/USER/Desktop/natalopetshopflutter/.worktrees/unified-admin-product-form`. Write the report to `.superpowers/sdd/task-1-report.md` with status, commits, tests, and concerns.
