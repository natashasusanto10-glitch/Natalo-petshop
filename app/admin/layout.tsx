"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { AdminNav } from "@/components/AdminNav";

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();

  useEffect(() => {
    document.documentElement.dataset.admin = "true";
    return () => {
      delete document.documentElement.dataset.admin;
    };
  }, []);

  // Login page gets no sidebar
  if (pathname === "/admin/login") {
    return <>{children}</>;
  }

  return <AdminNav>{children}</AdminNav>;
}
