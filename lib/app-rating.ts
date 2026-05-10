/**
 * App rating prompt manager — request native iOS review dialog
 * (SKStoreReviewController) di moment yang tepat.
 *
 * Strategy:
 * - Track jumlah successful order via localStorage
 * - Setelah order ke-3, prompt review (Apple cap 3 prompts/year per user)
 * - Setelah prompt, mark sudah ditampilkan agar gak spam
 * - Skip kalau di web non-Capacitor (gak ada native review dialog)
 */

const ORDERS_KEY = "natalo:successful-orders";
const COUNTED_ORDERS_KEY = "natalo:counted-order-ids";
const PROMPTED_KEY = "natalo:rating-prompted";
const PROMPT_AT_ORDER_COUNT = 3;

function getCountedOrderIds(): string[] {
  if (typeof window === "undefined") return [];
  try {
    return JSON.parse(localStorage.getItem(COUNTED_ORDERS_KEY) ?? "[]");
  } catch {
    return [];
  }
}

function markOrderCounted(orderId: string) {
  if (typeof window === "undefined") return;
  const ids = getCountedOrderIds();
  if (!ids.includes(orderId)) {
    ids.push(orderId);
    localStorage.setItem(COUNTED_ORDERS_KEY, JSON.stringify(ids));
  }
}

/**
 * Increment successful order counter. Call ini di order success page.
 * Returns boolean: did we trigger rating prompt?
 *
 * @param orderId - dedup per-order. Counter cuma incremented sekali per orderId,
 *                  walaupun user buka order page berkali-kali.
 */
export async function trackSuccessfulOrder(orderId: string): Promise<boolean> {
  if (typeof window === "undefined") return false;

  // Dedup: kalau order ID ini sudah pernah di-count, skip
  if (getCountedOrderIds().includes(orderId)) return false;
  markOrderCounted(orderId);

  // Increment counter
  const current = parseInt(localStorage.getItem(ORDERS_KEY) ?? "0", 10);
  const next = current + 1;
  localStorage.setItem(ORDERS_KEY, String(next));

  // Sudah pernah prompt? Jangan trigger lagi.
  if (localStorage.getItem(PROMPTED_KEY)) return false;

  // Belum sampai threshold? Skip.
  if (next < PROMPT_AT_ORDER_COUNT) return false;

  // Trigger native review dialog
  const triggered = await maybePromptReview();
  if (triggered) {
    localStorage.setItem(PROMPTED_KEY, String(Date.now()));
  }
  return triggered;
}

/**
 * Force prompt native review dialog (iOS SKStoreReviewController).
 * Apple internally rate-limit ini — max 3 prompts/year per user, jadi aman
 * dipanggil multiple times tanpa spam.
 *
 * Pakai ini juga untuk manual trigger dari menu (mis. tombol "Beri Rating"
 * di settings page).
 */
export async function maybePromptReview(): Promise<boolean> {
  if (typeof window === "undefined") return false;

  try {
    const { InAppReview } = await import("@capacitor-community/in-app-review");
    await InAppReview.requestReview();
    return true;
  } catch (err) {
    // Web / non-Capacitor — silent no-op
    return false;
  }
}

/**
 * Reset counter (untuk testing). Jangan dipakai di production.
 */
export function resetRatingState() {
  if (typeof window === "undefined") return;
  localStorage.removeItem(ORDERS_KEY);
  localStorage.removeItem(PROMPTED_KEY);
  localStorage.removeItem(COUNTED_ORDERS_KEY);
}
