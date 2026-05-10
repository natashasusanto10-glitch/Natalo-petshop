import type { Metadata, Viewport } from "next";
import { Nunito } from "next/font/google";
import "./globals.css";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { PWARegister } from "@/components/PWARegister";
import { InstallPrompt } from "@/components/InstallPrompt";
import { StoreOnly } from "@/components/StoreOnly";
import { BottomNavigation } from "@/components/BottomNavigation";
import { WhatsAppFloat } from "@/components/WhatsAppFloat";
import { ToastProvider } from "@/components/Toast";
import { AppSplashOverlay } from "@/components/AppSplashOverlay";

const nunito = Nunito({
  subsets: ["latin"],
  weight: ["400", "600", "700", "800", "900"],
  display: "swap",
  variable: "--font-nunito",
});

const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
const googleVerification = process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION;

export const metadata: Metadata = {
  title: {
    default: `${brand} | Toko Hewan Peliharaan Medan`,
    template: `%s | ${brand}`,
  },
  description:
    "Toko hewan peliharaan online terpercaya di Medan. Produk kucing, anjing, ikan, aksesoris, obat, dan vitamin hewan. Pengiriman ke seluruh Indonesia.",
  keywords: [
    "petshop medan",
    "toko hewan peliharaan",
    "makanan kucing",
    "makanan anjing",
    "akuarium medan",
    "obat hewan",
    "vitamin hewan",
    "royal canin medan",
    "whiskas medan",
    "natalo petshop",
  ],
  manifest: "/manifest.json",
  metadataBase: new URL(siteUrl),
  alternates: {
    canonical: siteUrl,
  },
  openGraph: {
    type: "website",
    siteName: brand,
    locale: "id_ID",
    url: siteUrl,
    title: `${brand} | Toko Hewan Peliharaan Medan`,
    description:
      "Toko hewan peliharaan online terpercaya di Medan. Produk kucing, anjing, ikan, aksesoris, obat, dan vitamin.",
    images: [
      {
        url: "/icons/icon-512x512.png",
        width: 512,
        height: 512,
        alt: brand,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: brand,
    description: "Toko hewan peliharaan online terpercaya di Medan.",
    images: ["/icons/icon-512x512.png"],
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: brand,
    // iOS PWA splash screens — di-generate via `node scripts/generate-ios-splash.mjs`
    // Output di public/splash/. Tanpa ini, iPhone tampilkan layar putih saat app load.
    // Fallback PNG di akhir = catch-all untuk device yang resolusinya tidak match
    // satupun media query di atas.
    startupImage: [
      // Light mode + size-specific
      { url: "/splash/iphone-16-pro-max-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 440px) and (device-height: 956px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-16-pro-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 402px) and (device-height: 874px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-15-pro-max-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 430px) and (device-height: 932px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-15-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 393px) and (device-height: 852px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-14-pro-max-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 428px) and (device-height: 926px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-14-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 390px) and (device-height: 844px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-12-mini-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 375px) and (device-height: 812px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-xs-max-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 414px) and (device-height: 896px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-xr-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 414px) and (device-height: 896px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)" },
      { url: "/splash/iphone-8-plus-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 414px) and (device-height: 736px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-se-portrait.png", media: "(prefers-color-scheme: light) and (device-width: 375px) and (device-height: 667px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)" },

      // Dark mode + size-specific (PNG sama — brand blue tetap konsisten gelap/terang)
      { url: "/splash/iphone-16-pro-max-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 440px) and (device-height: 956px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-16-pro-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 402px) and (device-height: 874px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-15-pro-max-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 430px) and (device-height: 932px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-15-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 393px) and (device-height: 852px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-14-pro-max-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 428px) and (device-height: 926px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-14-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 390px) and (device-height: 844px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-12-mini-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 375px) and (device-height: 812px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-xs-max-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 414px) and (device-height: 896px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-xr-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 414px) and (device-height: 896px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)" },
      { url: "/splash/iphone-8-plus-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 414px) and (device-height: 736px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)" },
      { url: "/splash/iphone-se-portrait.png", media: "(prefers-color-scheme: dark) and (device-width: 375px) and (device-height: 667px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)" },

      // Universal fallback (no media query) — ditemui kalau dua kategori di atas tidak match
      { url: "/splash/fallback.png" },
    ],
  },
  icons: {
    icon: [
      { url: "/favicon-32x32.png", sizes: "32x32", type: "image/png" },
      { url: "/icons/icon-192x192.png", sizes: "192x192", type: "image/png" },
    ],
    apple: "/apple-touch-icon.png",
  },
  verification: googleVerification
    ? {
        google: googleVerification,
      }
    : undefined,
};

export const viewport: Viewport = {
  // theme-color media-aware: brand blue di kedua mode (light/dark) supaya
  // status bar PWA tetap konsisten brand, tidak ke-invert iOS dark mode.
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#1E5FBF" },
    { media: "(prefers-color-scheme: dark)", color: "#1E5FBF" },
  ],
  // Force light color-scheme supaya iOS PWA tidak auto-render dark splash.
  // Tanpa ini, iPhone dalam dark mode bisa render splash hitam meskipun
  // manifest background_color #1E5FBF.
  colorScheme: "light",
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="id" className={nunito.variable}>
      <head>
        <meta charSet="UTF-8" />
        <meta httpEquiv="Content-Type" content="text/html; charset=utf-8" />
      </head>
      <body>
        <PWARegister />
        <StoreOnly>
          <AppSplashOverlay />
          <Header />
        </StoreOnly>
        <main className="nat-main-shell">{children}</main>
        <StoreOnly>
          <Footer />
          <WhatsAppFloat />
          <BottomNavigation />
          <InstallPrompt />
        </StoreOnly>
        <ToastProvider />
      </body>
    </html>
  );
}
