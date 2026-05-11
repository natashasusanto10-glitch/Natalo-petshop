import type { NextConfig } from "next";
import bundleAnalyzer from "@next/bundle-analyzer";

const withBundleAnalyzer = bundleAnalyzer({
  enabled: process.env.ANALYZE === "true",
  openAnalyzer: false,
});

const nextConfig: NextConfig = {
  // Bundle optimization
  experimental: {
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
    return [
      {
        source: "/uploads/:path*",
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=31536000, immutable",
          },
        ],
      },
    ];
  },
};

export default withBundleAnalyzer(nextConfig);
