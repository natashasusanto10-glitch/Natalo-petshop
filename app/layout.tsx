import type { Metadata, Viewport } from "next";
import "./globals.css";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { PWARegister } from "@/components/PWARegister";
import { InstallPrompt } from "@/components/InstallPrompt";

const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

export const metadata: Metadata = {
  title: {
    default: `${brand} | Toko Hewan Peliharaan`,
    template: `%s | ${brand}`,
  },
  description: "Toko hewan peliharaan terpercaya. Pakan, aksesoris, dan kebutuhan hewan peliharaan kamu — lengkap, berkualitas, dikirim cepat.",
  manifest: "/manifest.json",
  metadataBase: new URL(siteUrl),
  openGraph: {
    type: "website",
    siteName: brand,
    locale: "id_ID",
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: brand,
  },
  icons: {
    icon: "/icon.svg",
    apple: "/icon.svg",
  },
};

export const viewport: Viewport = {
  themeColor: "#F97316",
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="id">
      <body>
        <PWARegister />
        <Header />
        <main>{children}</main>
        <Footer />
        <InstallPrompt />
      </body>
    </html>
  );
}
