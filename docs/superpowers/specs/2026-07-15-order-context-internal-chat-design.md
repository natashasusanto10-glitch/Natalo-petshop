# Order Context in NLCATTER Internal Chat

## Goal

Replace the `Hubungi admin` action in the member order list with NLCATTER's internal chat. The chat must identify the exact order selected by the customer, including completed or older orders, without opening WhatsApp or creating a separate room per order.

## Approved User Flow

1. The customer opens `Pesanan Saya` and opens the action sheet for any order.
2. `Hubungi admin` uses the same `ChatDotsBubbleIcon` used by the app header.
3. Tapping it closes the sheet and opens the existing `/chat` route.
4. The route receives an order context containing the selected order number and its visible summary.
5. The internal chat shows the selected order as an order-context card so both customer and admin know which order is being discussed.
6. Selecting another old or new order later adds that order's context to the same customer–admin conversation. It does not create another chat room.

## Data and Security

The Flutter app passes an order context through the existing chat-route argument contract. The server remains authoritative: it validates that the authenticated customer owns the supplied order number and rebuilds the order summary from stored data before accepting it. Client-provided totals, statuses, and product details are display hints only and must not authorize access.

The context contains the existing order fields needed by the chat card: order number, order status, payment status, total, item count, proof state, and creation date. Existing server-side deduplication and message contracts remain unchanged.

## UI Changes

- Replace the generic action-sheet chat icon with `ChatDotsBubbleIcon` so it matches the header chat icon.
- Replace the WhatsApp launcher in the order-list action with navigation to NLCATTER's `/chat` route.
- Preserve the existing order-list sheet layout and all unrelated actions.
- Reuse the existing order-context card renderer in the chat screen; do not introduce a second visual contract.
- Keep the current NLCATTER blue/neutral styling and accessibility semantics.

## Error and Authentication Behavior

- If the customer is not authenticated, use the existing chat login gate and preserve the order context through the redirect.
- If the selected order is invalid or is not owned by the customer, the server rejects the context using the existing authorization behavior.
- Chat loading or sending errors continue to use the existing chat error UI.

## Testing

- A widget/unit test verifies that the action-sheet helper creates the context for the selected order rather than the latest order.
- A widget test verifies that `Hubungi admin` uses `ChatDotsBubbleIcon` and opens `/chat` with the selected order context.
- Existing chat-message parsing tests continue to cover `order_context` rendering.
- Run focused Flutter tests and `flutter analyze` on the affected files.

## Out of Scope

- New chat rooms per order.
- WhatsApp fallback for this action.
- Redesigning the chat room, order card, order detail screen, or other profile contact actions.
- Changes to order storage, checkout, or fulfillment.
