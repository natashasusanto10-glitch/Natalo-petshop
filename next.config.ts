import type { NextConfig } from "next";
import bundleAnalyzer from "@next/bundle-analyzer";
import { withSentryConfig } from "@sentry/nextjs";

const withBundleAnalyzer = bundleAnalyzer({
  enabled: process.env.ANALYZE === "true",
  openAnalyzer: false,
});

const nextConfig: NextConfig = {
  // Prisma client harus di-skip dari bundler Next.js — kalau ikut di-bundle
  // (default behavior di Next.js 16 Turbopack), yang ke-load adalah varian
  // `edge.js` yang wajib pakai `prisma://` URL (Data Proxy). Dengan dia jadi
  // external, Node.js `require` ambil langsung dari node_modules dan dapat
  // engine library normal yang menerima `postgresql://`.
  serverExternalPackages: ["@prisma/client", "prisma"],

  // Bundle optimization
  experimental: {
    // `viewTransition: true` DIBUANG di Next 16.3 — flag experimental-nya
    // dihapus dari tipe config (ada di 16.2.12 config-shared.d.ts:699,
    // hilang di 16.3.3), sehingga membiarkannya membuat `next build`
    // gagal type-check:
    //   error TS2353: 'viewTransition' does not exist in type
    //   'ExperimentalConfig'
    //
    // FITURNYA TIDAK HILANG, hanya flag-nya yang naik status dari
    // experimental — runtime 16.3.3 masih memuat viewTransitionClass /
    // viewTransitionName. Jadi ini pembuangan flag usang, bukan
    // pematian fitur.
    // Optimize CSS chunks — extract critical CSS, defer rest
    optimizePackageImports: [
      "lucide-react",
      "react-icons/io5",
      "@capacitor/core",
      "@capacitor/app",
      "@capacitor/browser",
      "@capacitor/share",
      "@capacitor/haptics",
      "@capacitor/network",
      "@capacitor/keyboard",
      "@capacitor/status-bar",
      "@capacitor/camera",
      "@capacitor/push-notifications",
      "@capacitor-community/in-app-review",
    ],
  },
  images: {
    formats: ["image/avif", "image/webp"],
    minimumCacheTTL: 60 * 60 * 24 * 30,
    remotePatterns: [
      { protocol: "https", hostname: "images.unsplash.com" },
      { protocol: "https", hostname: "res.cloudinary.com" },
      { protocol: "https", hostname: "**.supabase.co" },
      { protocol: "https", hostname: "**.supabase.in" },
      { protocol: "https", hostname: "lh3.googleusercontent.com" },
      { protocol: "https", hostname: "cdn.jsdelivr.net" },
      { protocol: "https", hostname: "placehold.co" },
      // UploadThing CDN
      { protocol: "https", hostname: "utfs.io" },
      { protocol: "https", hostname: "**.ufs.sh" },
      // Bunny CDN — thumbnail + MP4 dari Bunny Stream library
      // (URL pattern: https://vz-xxxxx.b-cdn.net/{guid}/thumbnail.jpg)
      { protocol: "https", hostname: "**.b-cdn.net" },
      // Shopee CDN — sumber gambar produk di prisma/products_import.json
      // (URL pattern: https://cf.shopee.co.id/file/...)
      { protocol: "https", hostname: "cf.shopee.co.id" },
      { protocol: "https", hostname: "**.shopee.co.id" },
      { protocol: "https", hostname: "down-id.img.susercontent.com" },
      // Allow localhost upload previews
      { protocol: "http", hostname: "localhost" },
      // QR code generation service
      { protocol: "https", hostname: "api.qrserver.com" },
    ],
  },
  async redirects() {
    // Canonical apex → www, TAPI kecualikan /.well-known/*.
    //
    // KENAPA: verifikasi Android App Links (autoVerify="true") dan iOS
    // Universal Links TIDAK mengikuti redirect. Selama apex
    // natalopetshop.com dijawab 307 ke www, Play Console melaporkan
    // "1 domain not verified / Failed domain checks" untuk apex — walau
    // file di www sendiri sudah benar. File-nya WAJIB dijawab 200 langsung
    // di host yang tercantum di intent-filter.
    //
    // PENTING: redirect ini hanya berlaku kalau redirect apex→www di
    // dashboard Vercel (Project → Domains) DIMATIKAN. Redirect level
    // domain Vercel jalan di edge sebelum Next.js, jadi tidak bisa
    // dikecualikan per-path dari sini.
    return [
      {
        // Named group `path` wajib — destination memakai `:path*`.
        source: "/:path((?!\\.well-known).*)",
        has: [{ type: "host", value: "natalopetshop.com" }],
        destination: "https://www.natalopetshop.com/:path",
        permanent: true,
      },
    ];
  },
  async headers() {
    // Security headers di-apply ke SEMUA path (source "/:path*").
    // Mandatory hardening untuk production. Reference: OWASP Secure Headers.
    const securityHeaders = [
      // HSTS — force HTTPS selama 2 tahun + include subdomains + preload
      // (eligible utk Chrome HSTS preload list).
      {
        key: "Strict-Transport-Security",
        value: "max-age=63072000; includeSubDomains; preload",
      },
      // Anti-clickjacking — refuse render di iframe luar (Vercel + same-origin OK).
      { key: "X-Frame-Options", value: "SAMEORIGIN" },
      // Hindari MIME sniffing attack.
      { key: "X-Content-Type-Options", value: "nosniff" },
      // Privacy: kirim referrer hanya saat same-origin atau https→https.
      { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
      // Disable browser API yg tidak dipakai (geolocation/microphone/camera
      // di-allow utk in-app camera upload — kalau perlu, hapus dari blocklist).
      {
        key: "Permissions-Policy",
        value: "browsing-topics=(), interest-cohort=(), payment=(self), microphone=(), geolocation=(self), camera=(self)",
      },
    ];
    const ffmpegHeaders = [
      { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
      { key: "Cross-Origin-Embedder-Policy", value: "require-corp" },
    ];

    return [
      {
        // Apply security headers ke semua path
        source: "/:path*",
        headers: securityHeaders,
      },
      {
        // FFmpeg.wasm butuh cross-origin isolated page supaya SharedArrayBuffer
        // tersedia (= multi-threaded encoding). Without these headers the
        // WASM runs single-threaded and a 30s clip can take 30-60s to
        // compress on iOS. Scoped to upload-capable routes so the rest of
        // the app stays free to embed cross-origin resources without
        // explicit CORP markers.
        //
        // NOTE: /feed itself (which hosts <FeedCreatePostSheet> via
        // <FeedUploadProvider>) deliberately does NOT get these headers
        // because the feed timeline loads UploadThing video/thumbnail
        // assets that don't return CORP headers — with require-corp the
        // feed would render as a wall of broken videos. The trade-off is
        // single-threaded compression when posting from /feed. Speed is
        // tuned via preset/crf in USER_VIDEO_CONFIG instead. Server-side
        // encoding (Bunny / Mux) would eliminate the dilemma entirely.
        source: "/feed/upload",
        headers: ffmpegHeaders,
      },
      {
        source: "/admin/feed/new",
        headers: ffmpegHeaders,
      },
      {
        // Static asset uploads — long-cache immutable
        source: "/uploads/:path*",
        headers: [
          { key: "Cache-Control", value: "public, max-age=31536000, immutable" },
        ],
      },
      {
        // Static info pages — content jarang berubah, cache 1 jam di CDN,
        // serve stale-while-revalidate 24 jam. Tetap "must-revalidate" di
        // browser sehingga reload manual ambil fresh copy.
        source: "/:path(tentang-kami|kebijakan-privasi|kebijakan-pengembalian|syarat-ketentuan|cara-pemesanan)",
        headers: [
          {
            key: "Cache-Control",
            value: "public, s-maxage=3600, stale-while-revalidate=86400",
          },
        ],
      },
      {
        // Deep-linking files — penting di-cache lama di CDN supaya
        // Apple/Google verifier cepat dapat response. assetlinks +
        // apple-app-site-association harus reachable saat user install
        // app pertama kali.
        source: "/.well-known/:file*",
        headers: [
          { key: "Cache-Control", value: "public, max-age=3600" },
          { key: "Content-Type", value: "application/json" },
        ],
      },
    ];
  },
};

// Compose bundleAnalyzer + Sentry wrappers. Order matters — Sentry harus
// outermost supaya source map upload & instrumentation jalan saat build.
// Sentry options:
//   - silent: tidak spam log di lokal dev kalau env Sentry tidak diset
//   - widenClientFileUpload: capture lebih banyak chunk untuk source map
//   - hideSourceMaps: tidak expose .map ke client (security)
//   - disableLogger: strip Sentry SDK debug log di production bundle
//   - automaticVercelMonitors: enable cron monitoring auto kalau pakai
//     Vercel cron
const sentryWebpackOptions = {
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  authToken: process.env.SENTRY_AUTH_TOKEN,
  silent: !process.env.CI,
  widenClientFileUpload: true,
  hideSourceMaps: true,
  disableLogger: true,
  automaticVercelMonitors: true,
};

export default withSentryConfig(withBundleAnalyzer(nextConfig), sentryWebpackOptions);
