// Self-destruct Service Worker.
//
// Konteks: PWA dihapus permanen dari Natalo Petshop web. Tapi user yang
// sudah pernah load site sebelum perubahan ini sudah punya SW lama (versi
// caching biasa) yang ke-install di browser-nya. SW lama itu masih intercept
// request dan kasih HTML/chunk cached yang sudah outdated → blank screen /
// chunk-not-found error setelah deploy.
//
// File ini DI-SERVE ke client lama saat browser mereka cek update SW (cek
// otomatis setiap navigation atau ~24 jam sekali). Saat install handler
// di sini jalan, SW langsung skipWaiting → activate handler langsung unregister
// dirinya sendiri + nuke semua cache `natalo-*` + reload semua tab/window
// supaya page baru di-fetch dari network tanpa SW interceptor.
//
// Setelah satu siklus (max ~24 jam, biasanya next visit), user pulih total.
// File ini dipertahankan sampai 100% user existing sudah ter-cleanup,
// lalu boleh dihapus + components/PWARegister.tsx juga.
//
// CACHE constant cuma version marker — browser bandingkan byte-by-byte
// sw.js terhadap yang sudah ter-install. Kalau beda → trigger install handler.
const CACHE = "natalo-cleanup-v1";

self.addEventListener("install", (event) => {
  // Langsung activate tanpa nunggu tab lama close.
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      try {
        // 1. Unregister diri sendiri — supaya navigation berikutnya tidak
        //    lewat SW lagi. Browser drop SW dari registry permanent.
        await self.registration.unregister();

        // 2. Nuke semua cache yg pernah kita buat (prefix "natalo-").
        const keys = await caches.keys();
        await Promise.all(
          keys.filter((k) => k.startsWith("natalo-")).map((k) => caches.delete(k))
        );

        // 3. Reload semua client (tab/window) yang dikontrol SW ini supaya
        //    user langsung dapat fresh page dari network. Tanpa ini, tab
        //    yg sudah open masih pakai HTML yg di-serve dari SW sampai
        //    user reload manual.
        const clients = await self.clients.matchAll({
          type: "window",
          includeUncontrolled: true,
        });
        for (const client of clients) {
          if ("navigate" in client) {
            // navigate same URL → reload tanpa SW (karena sudah unregister).
            client.navigate(client.url).catch(() => {});
          }
        }
      } catch (err) {
        // Best-effort. Kalau gagal, user kena 1x lagi siklus berikutnya.
        // Tidak melempar — biarkan SW activate clean.
        console.warn("[sw cleanup] failed:", err);
      }
    })()
  );
});

// Fetch handler MINIMAL — pass-through ke network tanpa intervensi cache.
// Selama SW masih aktif (sebelum activate selesai unregister), request tetap
// jalan normal.
self.addEventListener("fetch", () => {
  // No-op. Browser fallback ke network default.
});
