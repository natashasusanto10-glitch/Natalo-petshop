# Feed mockup review — 5 October 2026

## Deliverable

Interactive mockup at http://127.0.0.1:8770/admin/feed. Open **Tambah postingan** or **Edit** from the list. This is a local proposal using example records and generated sample covers, not the production implementation. Reload resets the demo.

## Design decisions

- Use the existing Natalo admin typography, blue palette, navigation, shared dialog and motion tokens.
- Search by title, author or linked product; separate content format from publication/processing status.
- Keep edit and preview readily accessible; put moderation in the overflow menu. Preserve community ownership: community posts have no admin edit action.
- Group creation into media/content, products and optional notifications. Support video, product video and promo; no additional specification fields.
- Preview follows the structure observed in `components/feed/FeedVideoCard.tsx`: media, social indicators, linked-product pill, creator, official label and caption. It is an approximation, not an exact reuse of the customer component.
- Keep upload/transcoding and notification services untouched. The demo selects sample media and simulates preparation; it uploads no files and sends no notifications.
- Retain processing/hidden status when editing. Restoring incomplete media keeps it waiting for video. Cancelling moderation does not apply the change.

## Review and corrections

- Moved preview social indicators above the product pill to avoid overlap.
- Positioned the mobile save bar above existing bottom navigation; measured its bottom at 772px in an 844px viewport.
- Avoided focus-driven scroll jumps on form transitions.
- Removed video play indicator from photo posts.
- Changed summary label to “Gagal diproses” to distinguish failed videos from the attention filter that also includes processing videos.
- Retained thousands separators for promo prices and added promo price/date validation.

## Observed checks

- Local viewer build completed successfully with esbuild.
- Search for “kaniva” returned one linked-product post.
- Attention filter returned two example posts: processing and failed.
- Hide confirmation opened with optional reason and Cancel returned without hiding the post.
- Preview dialog received focus; Escape dismissed it; it could be reopened.
- Filled title/caption updated the customer preview. Sample-media preparation disabled publishing while busy, then re-enabled it.
- Saving a sample post returned to the list with waiting/processing status and a local success notice.
- Desktop reviewed at 1440×1000; mobile at 390×844. No horizontal document overflow or recorded runtime errors on the checked mobile states.
- Static color calculations: muted text on white 4.81:1; primary-button text 6.91:1; success badge 6.54:1; danger badge 5.90:1. These are selected color pairs, not a full WCAG certification.
- Dialog enters in 200ms, exits in 120ms. Hover feedback uses 160ms; form and notice enter in 200ms. Reduced-motion rules suppress custom animation. Actual frame rate and assistive-technology behavior were not measured.

## Subjective design assessment

| Area | Score | Basis |
|---|---:|---|
| Visual UI | 8.7/10 | Consistent hierarchy, spacing, sober palette and readable state badges |
| Workflow UX | 8.5/10 | Search, clear actions, grouped fields, preview and guarded moderation |
| Motion design | 8.5/10 | Short state feedback with reduced-motion support; no frame-rate measurement |

Remaining production work: integrate real media/upload progress, actual promo and notification validation, quotas and send-test action, cursor pagination, reconciliation and permanent-deletion flows; reuse the actual customer renderer for exact preview parity. Unsaved-change confirmation covers the mockup Back/Cancel buttons, not browser close/reload. Do not treat this mockup as verification of backend services.

## Screenshots

- `implementation-review/feed-list-mockup.png`
- `implementation-review/feed-editor-mockup.png`
- `implementation-review/feed-mobile-mockup.png`
