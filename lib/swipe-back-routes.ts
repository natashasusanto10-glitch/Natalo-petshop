import { shouldHideBottomNav } from "./navigation";

export type SwipeBackRouteConfig = {
  enableSwipeBack: boolean;
};

const ROOT_ROUTES = new Set([
  "/",
  "/products",
  "/produk",
  "/kategori",
  "/feed",
  "/member",
  "/cart",
]);

const EXPLICIT_ENABLE_PATTERNS: RegExp[] = [
  /^\/checkout\/addresses\/?$/,
  /^\/feed\/upload\/?$/,
  /^\/products\/[^/]+\/?$/,
  /^\/produk\/[^/]+\/?$/,
];

const DISABLE_PATTERNS: RegExp[] = [
  /^\/admin(\/|$)/,
  /^\/offline\/?$/,
  /^\/member\/login(\/|$)/,
  /^\/member\/register(\/|$)/,
  /^\/member\/forgot-password(\/|$)/,
  /^\/member\/reset-password(\/|$)/,
  /^\/checkout\/?$/,
  /^\/payment(\/|$)/,
  /^\/pembayaran(\/|$)/,
  /^\/pesanan\/[^/]+\/success\/?$/,
];

export function getSwipeBackRouteConfig(
  pathname: string | null | undefined,
): SwipeBackRouteConfig {
  const normalized = normalizePathname(pathname);

  if (!normalized) return { enableSwipeBack: false };
  if (ROOT_ROUTES.has(normalized)) return { enableSwipeBack: false };
  if (DISABLE_PATTERNS.some((pattern) => pattern.test(normalized))) {
    return { enableSwipeBack: false };
  }
  if (EXPLICIT_ENABLE_PATTERNS.some((pattern) => pattern.test(normalized))) {
    return { enableSwipeBack: true };
  }

  return { enableSwipeBack: shouldHideBottomNav(normalized) };
}

function normalizePathname(pathname: string | null | undefined): string {
  if (!pathname) return "";
  if (pathname.length > 1 && pathname.endsWith("/")) {
    return pathname.slice(0, -1);
  }
  return pathname;
}
