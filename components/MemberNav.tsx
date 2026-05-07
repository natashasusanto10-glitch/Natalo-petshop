"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const tabs = [
  { href: "/member", label: "Dashboard" },
  { href: "/member/orders", label: "Pesanan" },
  { href: "/member/reviews", label: "Review" },
  { href: "/member/favorites", label: "Favorit" },
  { href: "/member/pets", label: "Hewan" },
  { href: "/akun/alamat", label: "Alamat" },
  { href: "/member/profile", label: "Profil" },
];

export function MemberNav() {
  const pathname = usePathname();

  return (
    <nav className="mt-6 flex gap-1 overflow-x-auto">
      {tabs.map((tab) => {
        const active =
          pathname === tab.href ||
          (tab.href === "/akun/alamat" && pathname.startsWith("/akun/alamat"));

        return (
          <Link
            key={tab.href}
            href={tab.href}
            className={`rounded-t-xl px-5 py-2.5 text-sm font-bold transition ${
              active ? "bg-white text-natalo-600" : "text-white/70 hover:text-white"
            }`}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
