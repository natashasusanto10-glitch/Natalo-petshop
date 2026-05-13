"use client";

import type { ReactNode } from "react";
import { clearLocalCart } from "@/lib/cart";

interface LogoutButtonProps {
  redirectTo: string;
  className?: string;
  children?: ReactNode;
}

export function LogoutButton({ redirectTo, className = "", children }: LogoutButtonProps) {
  async function handleLogout() {
    await fetch("/api/auth/logout", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        scope: redirectTo.startsWith("/admin") ? "ADMIN" : "CUSTOMER",
      }),
    }).catch(() => {});
    clearLocalCart();
    window.location.replace(redirectTo);
  }

  return (
    <button
      onClick={handleLogout}
      className={`rounded-full border border-gray-200 px-5 py-2.5 text-sm font-semibold text-gray-700 transition hover:border-red-300 hover:text-red-500 ${className}`}
    >
      {children ?? "Keluar"}
    </button>
  );
}
