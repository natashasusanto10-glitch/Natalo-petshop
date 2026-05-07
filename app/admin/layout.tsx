import type { Metadata, Viewport } from "next";

export const metadata: Metadata = {
  title: {
    default: "Admin Natalo",
    template: "%s | Admin Natalo",
  },
  description: "Dashboard admin Natalo untuk mengelola toko.",
  manifest: "/admin-manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "Natalo Admin",
  },
};

export const viewport: Viewport = {
  themeColor: "#18181b",
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
};

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return children;
}
