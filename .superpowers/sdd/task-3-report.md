# Task 3 report

Status: complete

Commit: `f1f7171d` (`feat(products): defer video changes until save`)

Implemented:

- Added `ProductVideoDraft` imperative draft contract with metadata validation, trim support, TUS upload, Bunny processing state, and draft-only remove/replace behavior.
- Added pure compensation helpers in `lib/product/product-video-draft.ts`.
- Updated product video API to retain existing Bunny assets during replacement provisioning; cleanup is deferred to the parent save flow.
- Added tests for preserving the old GUID before save and hidden-product compensation intent.

Tests:

- `npx vitest run tests/product-video-draft.test.ts tests/admin-product-form.test.ts` — passed (9 tests).
- Requested command including `tests/product-video-serialize.test.ts` — product serialization file currently has no test suite, so Vitest reports the pre-existing empty-suite failure.
- `npx tsc --noEmit --pretty false` — blocked by missing `vitest` type declarations in this worktree.

Concerns:

- The parent unified form must call `commitAfterProductSave(productId)` after creating/updating the product and invoke the existing compensation DELETE endpoint on failure.
- Existing-video deletion intent is held in draft UI; parent integration should send the final removal mutation only after product save succeeds.

Follow-up fixes:

- POST provisioning is now side-effect free for the Product row; PATCH receives the new guid after parent save, attaches it, and then removes the old Bunny asset.
- Draft handle exposes `getDraftState()` and real trim controls while retaining 10–60 second constraints.
