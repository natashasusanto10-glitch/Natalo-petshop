# Unified Admin Product Form

## Purpose

Unify **Tambah Produk** and **Edit Produk** into one product-management experience. Admin completes all product information, including optional video, before saving. A successful create returns directly to the product list; it no longer redirects to Edit Produk to add a video.

## Scope

- Replace the divergent add/edit UIs with one shared `ProductForm` in `create` and `edit` modes.
- Keep the current Natalo admin color palette, typography, spacing, and admin UI primitives.
- Preserve the existing maximum of nine product photos.
- Make AI description generation available in both modes.
- Keep product, media, and variants consistent when saving fails or is cancelled.

This does not change public product-detail UI, product pricing rules, Bunny video processing, or the existing checkout flow.

## Form structure

The same three sections are used for both modes.

1. **Informasi Dasar**: compact photo rail, optional video rail, name, category, brand, and AI-assisted description.
2. **Informasi Penjualan**: variants, price, stock, and parent SKU.
3. **Pengiriman**: product weight.

Desktop retains the existing sticky section navigation and sticky save bar. Mobile uses the same section order without the sidebar. The only visible wording difference is the page title and primary action:

- Create: `Tambah Produk` / `Simpan Produk`
- Edit: `Edit Produk` / `Simpan Perubahan`

Both success paths navigate to `/admin/products`.

## Media interaction

### Photos

- At least one photo is required; the form cannot be saved otherwise.
- A maximum of nine photos is enforced in UI and server validation.
- Photos appear as compact thumbnails. The first thumbnail is the cover and receives a `Cover` marker.
- Clicking a thumbnail opens preview/edit; clicking its small `×` removes that item from the local form draft.
- Removing the cover promotes the next photo to cover immediately in the draft.
- Removing the last remaining photo is blocked with a clear inline message.

### Video

- Video is optional and uses the same compact rail concept, not a large upload block.
- Clicking its thumbnail opens preview or replacement selection; `×` marks the video for removal in the local draft.
- Existing validation remains: supported video type, source-size limit, and a final duration from 10 to 60 seconds after trimming.
- Existing videos are not deleted when `×` is clicked. The actual Bunny and database deletion happens only after the form save succeeds.

### Draft safety

`Batal` discards all unsaved media changes. It never deletes existing photos or video. This applies equally to create and edit.

## Save lifecycle

### Create without a video

1. Validate all product fields and at least one photo.
2. Create product, attributes, and variants in one database transaction.
3. Sync search index non-blockingly and redirect to the product list.

### Create with a video

The existing Bunny upload API needs a product ID. To retain one visible user flow without exposing a partial product, create mode uses a hidden creation state.

1. Validate the entire form before creating anything.
2. Create the product, attributes, and variants atomically with `creationState=creating` and inactive visibility.
3. In the same form, provision Bunny upload credentials, trim/upload the selected video, and mark it for processing.
4. When the upload is accepted, finalize the product: set `creationState=ready`, derive normal active state from the existing stock rules, sync search, then redirect to the product list.
5. If the upload/provisioning fails or the admin cancels, compensate by deleting the hidden creating product and any provisioned Bunny asset. The filled form remains available to retry.
6. A scheduled cleanup removes expired hidden creating products and their unfinished assets, protecting against a browser crash or lost connection.

`creationState` is an internal Product lifecycle field (`creating` or `ready`) added through a Prisma migration. Product-list and public-product queries exclude `creating`; this guarantees that an in-progress product appears in neither place.

### Edit

Edit uses the same client-side draft state. On save, the server transaction applies product fields, photos, and variants. Video replacement/removal is then finalized with compensating rollback behavior:

- If a replacement upload fails, retain the current published video.
- If deletion fails, retain the old video and report the failure; do not leave the product pointing to an absent asset.
- A successful update redirects to the product list.

## Variants, price, stock, and weight

- `VariantEditor` operates in controlled draft mode for both create and edit; it no longer independently saves changes while the parent form is unsaved.
- Variant changes, product details, and media references are committed together.
- For products with active variants, price, stock, and weight remain derived from the active variants as they are today.
- For single products, parent price must be greater than zero, stock must be zero or greater, and weight must be greater than zero.
- Parent SKU is only accepted for single products; variant products use their per-variant SKU values.

## AI description

- `AiDescriptionField` becomes product-mode agnostic.
- In create mode it calls a generation endpoint using the current name, category, brand, and draft variants; no persisted product ID is required.
- In edit mode it preserves the existing ability to generate from product context.
- Generation never saves automatically. The returned text replaces the editable draft only after the current overwrite confirmation.

## Validation and errors

- Client validation gives inline errors before submit; server schemas remain the source of truth.
- Save is disabled while a required upload or submit is active, and progress is shown in the existing admin style.
- Server validation errors map to human-readable Indonesian field labels, including individual variant rows.
- Network, Bunny provisioning, upload, and processing-state errors retain the full form draft and provide a retry action.
- All destructive actions are deferred to successful Save, except compensation cleanup of hidden create records that the current request created.

## Components and boundaries

- `ProductForm`: owns common draft state, validation, sections, save bar, and mode-specific labels.
- `ProductMediaRail`: owns compact thumbnail rendering, preview, add/remove intentions, and draft ordering.
- `ProductVideoDraft`: adapts the current metadata, trim, and TUS upload behavior to form-draft lifecycle.
- `VariantEditor`: exposes controlled draft input and validation to `ProductForm`.
- `AiDescriptionField`: accepts draft context and exposes generated editable text.
- Product APIs: own transaction boundaries, creation-state finalization, authorization, and compensation cleanup; browser code never receives Bunny secrets beyond scoped existing TUS credentials.

## Testing

- Unit tests for photo ordering, cover promotion, photo limits, and removal intent.
- Component tests for create/edit mode labels, AI description context, draft cancellation, and variant-derived field states.
- API tests for create with/without video, hidden creation-state visibility, failed-upload compensation, finalized visibility, and edit video replacement/removal.
- Regression tests for existing variant validation, SKU rules, product list filtering, public product queries, and Bunny webhook status handling.
- Manual admin QA: create a product with photos only, create with video, retry a failed upload, edit/reorder/remove photos, replace/remove a video, cancel unsaved changes, and confirm no hidden creating product appears in admin or public lists.
