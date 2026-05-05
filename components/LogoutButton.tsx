"use client";

import { useRouter } from "next/navigation";

interface LogoutButtonProps {
  redirectTo: string;
  className?: string;
}

export function LogoutButton({ redirectTo, className = "" }: LogoutButtonProps) {
  const router = useRouter();

  async function handleLogout() {
    await fetch("/api/auth/logout", { method: "POST" });
    router.push(redirectTo);
    router.refresh();
  }

  return (
    <button
      onClick={handleLogout}
      className={`rounded-full border border-gray-200 px-5 py-2.5 text-sm font-semibold text-gray-700 transition hover:border-red-300 hover:text-red-500 ${className}`}
    >
      Keluar
    </button>
  );
}
