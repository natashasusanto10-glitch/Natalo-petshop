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
  themeColor: "#1E88E5",
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
          <Header />
        </StoreOnly>
        <main className="pb-[70px] md:pb-0">{children}</main>
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
