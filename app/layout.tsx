import type { Metadata, Viewport } from "next";
import { Suspense } from "react";
import { Nunito } from "next/font/google";
import "./globals.css";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { WebOnlyFooter } from "@/components/WebOnlyFooter";
import { PWARegister } from "@/components/PWARegister";
import { NativeSwipeBackController } from "@/components/NativeSwipeBackController";
import { SwipeBackProvider } from "@/components/SwipeBackProvider";
import IOSSwipeBack from "@/components/IOSSwipeBack";
import { StoreOnly } from "@/components/StoreOnly";
import { BottomNavigation } from "@/components/BottomNavigation";
import { ToastProvider } from "@/components/Toast";
import { AppSplashOverlay } from "@/components/AppSplashOverlay";
import { PullToRefresh } from "@/components/PullToRefresh";
import { PageStatusBar } from "@/components/PageStatusBar";
import { KeyboardManager } from "@/components/KeyboardManager";
import { NetworkStatusBanner } from "@/components/NetworkStatusBanner";
import { DeepLinkHandler } from "@/components/DeepLinkHandler";
import { ViewTransitionsProvider } from "@/components/ViewTransitionsProvider";
import { PushNotificationManager } from "@/components/PushNotificationManager";
import { FeedUploadProvider } from "@/components/feed/FeedUploadProvider";
import { FeedUploadToast } from "@/components/feed/FeedUploadToast";
import { SpeedInsights } from "@vercel/speed-insights/next";

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
  // PWA dihapus (Mei 2026): appleWebApp config + iOS splash screens dilepas.
  // Mobile experience pindah ke Flutter native (App Store, bundle
  // com.natalo.petshop). Web sekarang regular web — install ke homescreen
  // cuma kasih bookmark, bukan standalone PWA.
  icons: {
    icon: [
      { url: "/favicon-32x32.png", sizes: "32x32", type: "image/png" },
      { url: "/icons/icon-192x192.png", sizes: "192x192", type: "image/png" },
    ],
    apple: "/apple-touch-icon.png",
  },
  // Smart App Banner — Safari iPhone auto-promote download Natalo Petshop
  // dari App Store saat user buka site di mobile Safari. Banner appear di
  // atas page dengan thumbnail icon app + tombol "View" / "Open" (kalau
  // already installed). App ID 6767888044 dari App Store Connect.
  //
  // app-argument: URL halaman saat ini dipassing ke app via Universal Links,
  // jadi tap banner buka app langsung di halaman yang sama (deep link).
  // Browser auto-substitute siteUrl base — untuk per-page argument yang
  // lebih spesifik, override metadata.other di per-page metadata.
  other: {
    "apple-itunes-app": `app-id=6767888044, app-argument=${siteUrl}`,
  },
  verification: googleVerification
    ? {
        google: googleVerification,
      }
    : undefined,
};

export const viewport: Viewport = {
  // Theme color putih: status bar/browser chrome terang dengan ikon gelap,
  // selaras dengan header dan bottom navigation putih.
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#ffffff" },
  ],
  // Force light color-scheme supaya iOS PWA tidak auto-render dark splash.
  // Tanpa ini, iPhone dalam dark mode bisa render splash gelap.
  colorScheme: "light",
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  viewportFit: "cover",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="id" className={nunito.variable}>
      <head>
        <meta charSet="UTF-8" />
        <meta httpEquiv="Content-Type" content="text/html; charset=utf-8" />
      </head>
      <body>
        <PWARegister />
        <NativeSwipeBackController />
        <IOSSwipeBack />
        <ViewTransitionsProvider />
        <StoreOnly>
          <AppSplashOverlay />
          <PullToRefresh />
          <KeyboardManager />
          <NetworkStatusBanner />
          <DeepLinkHandler />
          <PushNotificationManager />
          {/* App-wide default status bar — dark icons (black) untuk halaman
              dengan header putih (kebanyakan). Per-page override bisa mount
              <PageStatusBar iconColor="light" themeColor="#1E5FBF" /> di page
              dengan dark hero / brand blue full background. */}
          <PageStatusBar iconColor="dark" themeColor="#ffffff" />
          <Suspense fallback={null}>
            <Header />
          </Suspense>
        </StoreOnly>
        <FeedUploadProvider>
          <main className="nat-main-shell">
            <SwipeBackProvider>{children}</SwipeBackProvider>
          </main>
          <StoreOnly>
            <FeedUploadToast />
          </StoreOnly>
        </FeedUploadProvider>
        <StoreOnly>
          {/* Footer hanya tampil di web/PWA. Di Capacitor native shell (iOS
              .ipa / Android APK), bottom navigation + halaman /bantuan sudah
              cukup — footer besar redundant. Cegah footer + bottom nav muncul
              bersamaan di app. */}
          <WebOnlyFooter>
            <Footer />
          </WebOnlyFooter>
          <Suspense fallback={null}>
            <BottomNavigation />
          </Suspense>
        </StoreOnly>
        <ToastProvider />
        <SpeedInsights />
      </body>
    </html>
  );
}
