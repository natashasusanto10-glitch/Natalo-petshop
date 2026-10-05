"use client";

import "./admin-premium.css";
import "./feed-premium.css";
import "./promo-premium.css";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { AdminNav } from "@/components/AdminNav";
import { ToastProvider } from "@/components/admin/ui";

export default function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();

  useEffect(() => {
    document.documentElement.dataset.admin = "true";
    return () => {
      delete document.documentElement.dataset.admin;
    };
  }, []);

  // Login page gets no sidebar
  if (pathname === "/admin/login") {
    return <ToastProvider>{children}</ToastProvider>;
  }

  return (
    <ToastProvider>
      <AdminNav>{children}</AdminNav>
    </ToastProvider>
  );
}
