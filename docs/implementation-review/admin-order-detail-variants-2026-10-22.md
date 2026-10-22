# Admin order detail — implementation review (22 October 2026)

## Before implementation

Reviewed the approved mockup against the current admin detail page, schema, checkout item creation, print view and shared admin controls. The underlying OrderItem already stores variantId and variantLabel. The old page rendered only name, price and quantity. Checkout's saved name, price, quantity and variantLabel remain the primary historical data; no migration or order mutation is required for this display fix.

## Implemented

| Before | After | Why |
| --- | --- | --- |
| Selected variant invisible in purchased-item rows | Checkout variantLabel displayed beneath the item name; separate rows kept by OrderItem.id | Admin can distinguish the buyer's selections |
| Legacy label can be absent | Fall back to options from that exact linked variant, sorted by attribute/option position and labeled as current catalog data | Avoid inventing historical labels or selecting another variant |
| Simple products | No variant UI if both saved label and variant selection are absent | No unnecessary warning for products without variants |
| Genuine unresolved variant reference | Show its stored ID and an explicit request to confirm the selection | Avoid implying an unknown selection is a simple product |
| No product picture or SKU | Linked variant image/SKU, product image fallback, neutral missing-photo icon and copy control | Faster visual identification; SKU is explicitly current catalog data |
| Refund picker only showed the parent name | Include the same resolved variant label in refund choices | Reduce ambiguity between order lines |
| Small/uneven hierarchy | Locally bundled Plus Jakarta Sans, 28/24px heading, 16px section titles, 14px product names and readable supporting text | Consistent hierarchy and no external font request |
| Summary and products in one undifferentiated block | Separate purchased-item list and payment panel, with customer/shipping/proof sidebar | Clear grouping |
| Main actions buried in sidebar | Persistent next-action bar positioned above mobile navigation | Keep the next fulfillment step reachable |
| Payment confirmation submitted immediately | Dialog with transfer amount including manual unique code, pending lock and visible failure | Clear review before the existing authenticated server action |
| Proof opened another tab immediately | Enlarge in an accessible shared dialog with original-image link | Inspect payment evidence within the page |
| Pointer and keyboard dialog motion identical | Optional shared-dialog motion flag; new order dialogs disable animation for keyboard and respect reduced motion | Responsive feedback without keyboard delay |

## Preservation and review

- Existing authentication and server actions are retained. No real payment, refund, stock, shipment or order status action was executed during implementation.
- Paid/unpaid, pickup/delivery and terminal-order conditions were reviewed in source. Terminal orders have no action bar; pickup labels/actions follow their existing transitions.
- Subtotal, discounts, wallet usage, refunded amount and manual unique-code summary retain their existing formulas. Zero external totals do not gain a unique code in the confirmation dialog.
- No filter tabs were added.
- New font and OFL license copied under public/fonts because flutter_app is excluded from Vercel uploads.
- Shared AdminDialog motion option defaults to true, preserving other callers' behavior.
- Existing working-tree changes in the order page and ItemOutOfStockButton were preserved; no unrelated files were reverted.

## Checks and limits

Targeted ESLint passed for the order page, new client controls and shared dialog. Full TypeScript no-emit check returned exit 0. Diff whitespace check passed. No automated test suites were run. Production rendering, real-order data and live mutations have not been verified in this turn. This is an implementation in the working tree, not a deployment.
