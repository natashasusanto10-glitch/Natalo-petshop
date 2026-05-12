// CACHE name di-inject oleh scripts/bump-sw-version.mjs saat build:
// - Vercel build → "natalo-v-<commit-sha7>"   (traceable ke commit)
// - Local build  → "natalo-v-<sha7>-local"
// - Dev fallback → "natalo-vdev-<timestamp>"  (always unique, bust cache)
// Placeholder string ini WAJIB ada — script error keras kalau tidak match.
const CACHE = "__SW_CACHE_VERSION__";

const PRECACHE = [
  "/",
  "/cart",
  "/order-status",
  "/offline",
  "/manifest.json",
  "/favicon-32x32.png",
  "/apple-touch-icon.png",
  "/icons/icon-48x48.png",
  "/icons/icon-72x72.png",
  "/icons/icon-96x96.png",
  "/icons/icon-128x128.png",
  "/icons/icon-144x144.png",
  "/icons/icon-192x192.png",
  "/icons/icon-256x256.png",
  "/icons/icon-384x384.png",
  "/icons/icon-512x512.png",
  "/icons/icon-maskable-192x192.png",
  "/icons/icon-maskable-512x512.png",
  "/icons/mstile-150x150.png",
];

const SENSITIVE_PATH_PREFIXES = [
  "/admin",
  "/checkout",
  "/member",
  "/akun",
  "/account",
  "/profile",
  "/pesanan",
  "/orders",
  "/order",
  "/invoice",
  "/login",
  "/logout",
  "/auth",
  "/payment",
];

const SENSITIVE_QUERY_PARAMS = [
  "token",
  "access_token",
  "order_token",
  "ordertoken",
  "session",
  "session_id",
  "code",
  "auth",
];

function isSensitiveUrl(url) {
  const pathname = url.pathname.replace(/\/+$/, "") || "/";
  const isSensitivePath = SENSITIVE_PATH_PREFIXES.some(
    (path) => pathname === path || pathname.startsWith(`${path}/`)
  );
  const queryKeys = Array.from(url.searchParams.keys()).map((key) =>
    key.toLowerCase()
  );
  const hasSensitiveParam = SENSITIVE_QUERY_PARAMS.some((param) =>
    queryKeys.includes(param)
  );

  return isSensitivePath || hasSensitiveParam;
}

function isSensitivePageRequest(request) {
  const url = new URL(request.url);
  return url.origin === self.location.origin && isSensitiveUrl(url);
}

function shouldCacheResponse(response) {
  if (!response || response.status !== 200 || response.redirected) return false;

  const cacheControl =
    response.headers.get("Cache-Control")?.toLowerCase() ?? "";
  return !(
    cacheControl.includes("no-store") ||
    cacheControl.includes("private") ||
    cacheControl.includes("no-cache")
  );
}

async function cleanupSensitiveEntries(cacheName) {
  const cache = await caches.open(cacheName);
  const requests = await cache.keys();

  await Promise.all(
    requests
      .filter((request) => {
        const url = new URL(request.url);
        return url.origin === self.location.origin && isSensitiveUrl(url);
      })
      .map((request) => cache.delete(request))
  );
}

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches
      .open(CACHE)
      .then((c) => c.addAll(PRECACHE))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys.map((k) =>
            k === CACHE ? cleanupSensitiveEntries(k) : caches.delete(k)
          )
        )
      )
      .then(() => self.clients.claim())
  );
});

// Push notification handler
self.addEventListener("push", (e) => {
  if (!e.data) return;
  let payload = {
    title: "Natalo Petshop",
    body: "Ada update pesanan kamu!",
    url: "/order-status",
  };
  try {
    payload = { ...payload, ...e.data.json() };
  } catch {}
  e.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: "/icon.svg",
      badge: "/icon.svg",
      // tag = grouping key. Notification dgn tag sama akan REPLACE existing
      // (mis. order yg status berubah-ubah tidak stack 5 notif).
      tag: payload.tag,
      // Action buttons (Android only — iOS Safari ignore silently)
      actions: payload.actions ?? undefined,
      // SHIPPED status set true supaya user tidak miss notif "paket dikirim"
      requireInteraction: payload.requireInteraction === true,
      data: { ...(payload.data ?? {}), url: payload.url },
    })
  );
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = e.notification.data?.url || "/";
  e.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((clients) => {
        const existing = clients.find((c) => c.url.includes(url));
        if (existing) return existing.focus();
        return self.clients.openWindow(url);
      })
  );
});

// Fetch strategy:
// - API & auth → network only
// - Static assets → cache first
// - Pages → network first, fallback cache then /offline
self.addEventListener("fetch", (e) => {
  const { request } = e;
  const url = new URL(request.url);

  if (request.method !== "GET" || url.origin !== self.location.origin) return;
  if (url.pathname.startsWith("/api/")) return;

  if (
    url.searchParams.has("_rsc") ||
    request.headers.get("RSC") === "1" ||
    request.headers.get("Next-Router-Prefetch") === "1" ||
    request.headers.get("Accept")?.includes("text/x-component")
  ) {
    e.respondWith(fetch(request));
    return;
  }

  if (isSensitivePageRequest(request)) {
    e.respondWith(
      fetch(request).catch(() =>
        caches.match("/offline").then((res) => res ?? Response.error())
      )
    );
    return;
  }

  if (url.pathname.startsWith("/admin")) {
    e.respondWith(fetch(request).catch(() => caches.match("/offline")));
    return;
  }

  // Avoid serving stale Next.js app bundles after deployments.
  if (url.pathname.startsWith("/_next/")) {
    e.respondWith(fetch(request));
    return;
  }

  if (/\.(png|jpg|jpeg|svg|webp|ico|woff2?)$/.test(url.pathname)) {
    e.respondWith(
      caches.match(request).then(
        (cached) =>
          cached ??
          fetch(request).then((res) => {
            if (shouldCacheResponse(res)) {
              const clone = res.clone();
              caches.open(CACHE).then((c) => c.put(request, clone));
            }
            return res;
          })
      )
    );
    return;
  }

  e.respondWith(
    fetch(request)
      .then((res) => {
        if (shouldCacheResponse(res)) {
          const clone = res.clone();
          caches.open(CACHE).then((c) => c.put(request, clone));
        }
        return res;
      })
      .catch(() =>
        caches
          .match(request)
          .then((cached) => cached ?? caches.match("/offline"))
      )
  );
});
