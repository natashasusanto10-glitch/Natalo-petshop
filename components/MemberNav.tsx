"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const tabs = [
  { href: "/member", label: "Dashboard" },
  { href: "/member/orders", label: "Pesanan" },
  { href: "/member/profile", label: "Profil" },
];

export function MemberNav() {
  const pathname = usePathname();

  return (
    <nav className="mt-6 flex gap-1">
      {tabs.map((tab) => (
        <Link
          key={tab.href}
          href={tab.href}
          className={`rounded-t-xl px-5 py-2.5 text-sm font-bold transition ${
            pathname === tab.href
              ? "bg-white text-orange-500"
              : "text-white/70 hover:text-white"
          }`}
        >
          {tab.label}
        </Link>
      ))}
    </nav>
  );
}
