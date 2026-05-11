/**
 * Central cart state — localStorage primary + server sync untuk member.
 *
 * Strategi:
 * - localStorage = source of truth untuk UI cepat
 * - Member yang login: setiap perubahan di-debounce 500ms lalu PUT ke /api/cart
 * - On page load (boot): kalau member, fetch /api/cart dan merge ke local
 * - On login: panggil mergeFromServer() untuk pull + merge
 * - On logout: clear local cart (dipanggil dari LogoutButton)
 *
 * Semua mutate harus lewat fungsi di sini supaya sync server jalan.
 */

export type CartItem = {
  productId: string;
  /** Slug produk — dipakai untuk link "klik di cart kembali ke PDP".
   *  Optional supaya legacy cart items (sebelum field ini ada) tidak break. */
  slug?: string;
  variantId?: string | null;
  variantLabel?: string | null;
  name: string;
  price: number;
  quantity: number;
  subtotal?: number;
  weightGram: number;
  imageUrl?: string | null;
  stock?: number | null;
};

const LEGACY_STORAGE_KEY = "cart";
const GUEST_STORAGE_KEY = "cart:guest";
const OWNER_KEY = "cart:owner";
const EVENT_NAME = "cart-updated";
const AUTH_EVENT_NAME = "auth-updated";
const DEBOUNCE_MS = 500;

function isBrowser() {
  return typeof window !== "undefined";
}

export function loadCart(): CartItem[] {
  if (!isBrowser()) return [];
  migrateLegacyGuestCart();
  try {
    const raw = localStorage.getItem(activeStorageKey());
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    localStorage.removeItem(activeStorageKey());
    return [];
  }
}

function writeLocal(items: CartItem[]) {
  if (!isBrowser()) return;
  localStorage.setItem(activeStorageKey(), JSON.stringify(items));
  window.dispatchEvent(new Event(EVENT_NAME));
}

function activeOwner() {
  if (!isBrowser()) return "guest";
  return localStorage.getItem(OWNER_KEY) || "guest";
}

function storageKeyForOwner(owner: string) {
  return owner === "guest" ? GUEST_STORAGE_KEY : `cart:user:${owner}`;
}

function activeStorageKey() {
  return storageKeyForOwner(activeOwner());
}

function readStorage(key: string): CartItem[] {
  if (!isBrowser()) return [];
  try {
    const raw = localStorage.getItem(key);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    localStorage.removeItem(key);
    return [];
  }
}

function writeStorage(key: string, items: CartItem[]) {
  if (!isBrowser()) return;
  localStorage.setItem(key, JSON.stringify(items));
}

function setActiveOwner(owner: string) {
  if (!isBrowser()) return;
  localStorage.setItem(OWNER_KEY, owner);
}

function migrateLegacyGuestCart() {
  if (!isBrowser()) return;
  const legacy = readStorage(LEGACY_STORAGE_KEY);
  if (legacy.length > 0 && !localStorage.getItem(GUEST_STORAGE_KEY)) {
    writeStorage(GUEST_STORAGE_KEY, legacy);
  }
  localStorage.removeItem(LEGACY_STORAGE_KEY);
}

function dispatchCartUpdated() {
  if (!isBrowser()) return;
  window.dispatchEvent(new Event(EVENT_NAME));
}

export function dispatchAuthUpdated() {
  if (!isBrowser()) return;
  window.dispatchEvent(new Event(AUTH_EVENT_NAME));
}

export function switchToGuestCart() {
  if (!isBrowser()) return;
  setActiveOwner("guest");
  memberStatus = "guest";
  currentMemberId = null;
  dispatchCartUpdated();
}

// ── Server sync ────────────────────────────────────────────────────
let memberStatus: "unknown" | "guest" | "member" = "unknown";
let currentMemberId: string | null = null;
let pushTimer: ReturnType<typeof setTimeout> | null = null;
let pendingItems: CartItem[] | null = null;

async function checkAuth(): Promise<boolean> {
  if (!isBrowser()) return false;
  if (memberStatus === "member") return true;
  if (memberStatus === "guest") return false;
  try {
    const res = await fetch("/api/auth/me", { cache: "no-store" });
    const data = await res.json();
    if (data?.id && data?.name) {
      memberStatus = "member";
      currentMemberId = data.id;
      setActiveOwner(data.id);
    } else {
      memberStatus = "guest";
      currentMemberId = null;
      setActiveOwner("guest");
      dispatchCartUpdated();
    }
    return memberStatus === "member";
  } catch {
    memberStatus = "guest";
    currentMemberId = null;
    setActiveOwner("guest");
    dispatchCartUpdated();
    return false;
  }
}

function schedulePush(items: CartItem[]) {
  pendingItems = items;
  if (pushTimer) clearTimeout(pushTimer);
  pushTimer = setTimeout(async () => {
    pushTimer = null;
    const itemsToSend = pendingItems;
    pendingItems = null;
    if (!itemsToSend) return;
    if (!(await checkAuth())) return;
    try {
      await fetch("/api/cart", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items: itemsToSend }),
      });
    } catch {
      /* offline / network error — local cart tetap utuh, retry next mutation */
    }
  }, DEBOUNCE_MS);
}

export function saveCart(items: CartItem[]) {
  writeLocal(items);
  schedulePush(items);
}

// ── Merge utility ──────────────────────────────────────────────────
function cartKey(productId: string, variantId?: string | null) {
  return `${productId}:${variantId ?? ""}`;
}

function mergeItems(local: CartItem[], server: CartItem[]): CartItem[] {
  const map = new Map<string, CartItem>();
  // Server first → kalau ada konflik, ambil qty max dari local atau server
  for (const item of server) {
    map.set(cartKey(item.productId, item.variantId), { ...item });
  }
  for (const item of local) {
    const key = cartKey(item.productId, item.variantId);
    const existing = map.get(key);
    if (existing) {
      // Konflik: ambil qty max (asumsi user mau item yang lebih banyak)
      const max = Math.max(existing.quantity, item.quantity);
      const cap = item.stock ?? existing.stock ?? Infinity;
      map.set(key, { ...existing, ...item, quantity: Math.min(max, cap) });
    } else {
      map.set(key, item);
    }
  }
  return Array.from(map.values());
}

/**
 * Pull cart dari server, merge dengan local, simpan hasil ke local + push balik ke server.
 * Dipanggil saat:
 * - Page load (sekali per session)
 * - Setelah login (LogoutButton tidak panggil ini, login form yg panggil)
 */
export async function mergeFromServer(): Promise<void> {
  if (!isBrowser()) return;
  migrateLegacyGuestCart();
  // Force re-check auth
  memberStatus = "unknown";
  const isMember = await checkAuth();
  if (!isMember) return;
  try {
    const res = await fetch("/api/cart", { cache: "no-store" });
    if (!res.ok) return;
    const data = await res.json();
    const serverItems: CartItem[] = Array.isArray(data?.items) ? data.items : [];
    const guestItems = readStorage(GUEST_STORAGE_KEY);
    const userItems = readStorage(storageKeyForOwner(currentMemberId ?? activeOwner()));
    const localItems = mergeItems(guestItems, userItems);
    const merged = mergeItems(localItems, serverItems);
    setActiveOwner(currentMemberId ?? activeOwner());
    writeLocal(merged);
    writeStorage(GUEST_STORAGE_KEY, []);
    // Push merged back to server (biar server up-to-date juga)
    schedulePush(merged);
  } catch {
    /* ignore — local cart tetap dipakai */
  }
}

/**
 * Clear local cart. Dipanggil saat logout — server cart dibiarkan, akan di-pull lagi
 * saat user yang sama login di device manapun.
 */
export function clearLocalCart() {
  if (!isBrowser()) return;
  const owner = activeOwner();
  localStorage.removeItem(storageKeyForOwner(owner));
  localStorage.removeItem(LEGACY_STORAGE_KEY);
  writeStorage(GUEST_STORAGE_KEY, []);
  setActiveOwner("guest");
  memberStatus = "guest";
  currentMemberId = null;
  dispatchCartUpdated();
  dispatchAuthUpdated();
}

/**
 * Setelah checkout sukses (order created), clear cart di local + server.
 */
export async function clearCartEverywhere() {
  if (!isBrowser()) return;
  localStorage.removeItem(activeStorageKey());
  dispatchCartUpdated();
  if (await checkAuth()) {
    try {
      await fetch("/api/cart", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items: [] }),
      });
    } catch {
      /* ignore */
    }
  }
}

/**
 * Panggil sekali di app boot (Header / layout client component) untuk ambil cart server.
 */
export async function bootstrapCartSync() {
  await mergeFromServer();
}
