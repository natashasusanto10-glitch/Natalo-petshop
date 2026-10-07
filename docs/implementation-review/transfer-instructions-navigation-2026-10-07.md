# Transfer instruction navigation

- Order success: manual transfer instruction action now sends typed route arguments with a payment-section focus flag.
- Normal order-detail actions continue passing OrderSummary and open at the header.
- Order detail waits for its initial refresh, lays out the payment-section anchor, positions it at the viewport start, then reveals the content. This avoids showing the header followed by a long automatic scroll.
- The section is laid out inside a finite Column so its anchor exists even when initially outside the viewport; ensureVisible does not depend on a lazy child already being built.
- Focus runs once. Refresh/upload cannot reset the buyer's scroll position.
- If payment is already complete or the action card is absent, the page opens normally rather than staying in a loading state.
- Existing instructions and proof upload retained; no extra upload button, payment API changes or money calculations.
- Reviewed route compatibility, async mounted guards and hidden-content input/accessibility exclusion.
- Formatting and diff whitespace checks completed. Native device navigation still needs verification in the next Flutter build; no automated tests or deployment performed for this change.
