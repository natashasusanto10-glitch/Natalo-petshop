import type { NextConfig } from "next";
import bundleAnalyzer from "@next/bundle-analyzer";

const withBundleAnalyzer = bundleAnalyzer({
  enabled: process.env.ANALYZE === "true",
  openAnalyzer: false,
});

const nextConfig: NextConfig = {
  // Bundle optimization
  experimental: {
    // View Transitions API — enable browser-level cross-fade between
    // route navigations. Works di Chrome 126+ (Capacitor WebView modern OK).
    // Browser yang belum support fallback ke instant nav, no regression.
    viewTransition: true,
    // Optimize CSS chunks — extract critical CSS, defer rest
    optimizePackageImports: [
      "lucide-react",
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
      // UploadThing CDN
      { protocol: "https", hostname: "utfs.io" },
      { protocol: "https", hostname: "**.ufs.sh" },
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

    return [
      {
        // Apply security headers ke semua path
        source: "/:path*",
        headers: securityHeaders,
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

export default withBundleAnalyzer(nextConfig);
