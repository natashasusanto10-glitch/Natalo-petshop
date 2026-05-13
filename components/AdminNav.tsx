"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { LogoutButton } from "./LogoutButton";

type NavGroup = { section: string; items: NavItem[] };
type NavItem = { href: string; label: string; icon: ReactNode; exact?: boolean };

const NAV_GROUPS: NavGroup[] = [
  {
    section: "Operasi",
    items: [
      {
        href: "/admin/dashboard",
        label: "Dashboard",
        exact: true,
        icon: <Glyph d="M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z" />,
      },
      {
        href: "/admin/orders",
        label: "Pesanan",
        icon: <Glyph d="M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 3h6v4H9zM9 12h6M9 16h4" />,
      },
      {
        href: "/admin/products",
        label: "Produk",
        icon: <Glyph d="M20 7H4a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1V8a1 1 0 0 0-1-1ZM16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2" />,
      },
      {
        href: "/admin/categories",
        label: "Kategori",
        icon: <Glyph d="M3 6h18M3 12h18M3 18h18" />,
      },
      {
        href: "/admin/stock",
        label: "Stok & Gudang",
        icon: <Glyph d="M5 8h14M3 8a2 2 0 1 1 4 0v12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2V8a2 2 0 1 1 4 0M9 8V6a2 2 0 1 1 4 0v2m4 0V6a2 2 0 1 1 4 0v2" />,
      },
    ],
  },
  {
    section: "Marketing",
    items: [
      {
        href: "/admin/vouchers",
        label: "Voucher",
        icon: <Glyph d="M2 9.5V7a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v2.5a2 2 0 0 0 0 4V17a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-3.5a2 2 0 0 0 0-4ZM10 8v8" extra="m" />,
      },
      {
        href: "/admin/brands",
        label: "Brand",
        icon: <Glyph d="M12 2 2 7l10 5 10-5-10-5ZM2 17l10 5 10-5M2 12l10 5 10-5" />,
      },
      {
        href: "/admin/broadcast",
        label: "Broadcast Notifikasi",
        icon: <Glyph d="M3 11l18-8-5 18-4-9-9-1zM13 12l8-9" />,
      },
    ],
  },
  {
    section: "Pelanggan",
    items: [
      {
        href: "/admin/customers",
        label: "Customers",
        icon: <Glyph d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" />,
      },
      {
        href: "/admin/reviews",
        label: "Reviews",
        icon: <Glyph d="m12 2 3.09 6.26L22 9.27l-5 4.87L18.18 21 12 17.77 5.82 21 7 14.14 2 9.27l6.91-1.01L12 2Z" />,
      },
    ],
  },
  {
    section: "Sistem",
    items: [
      {
        href: "/admin/reports",
        label: "Laporan",
        icon: <Glyph d="M18 20V10M12 20V4M6 20v-6" />,
      },
      {
        href: "/admin/settings",
        label: "Pengaturan",
        icon: <Glyph d="M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82 1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z" />,
      },
    ],
  },
];

function Glyph({ d, extra }: { d: string; extra?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" className="h-[18px] w-[18px]">
      <path d={d} />
      {extra && <path d="" />}
    </svg>
  );
}

function isActiveItem(pathname: string, item: NavItem) {
  if (item.exact) return pathname === item.href;
  return pathname === item.href || pathname.startsWith(`${item.href}/`);
}

function NavList() {
  const pathname = usePathname();

  return (
    <nav className="flex-1 overflow-y-auto px-3 pb-4">
      {NAV_GROUPS.map((group) => (
        <div key={group.section} className="mt-1">
          <p className="px-3 pb-1.5 pt-3 text-[10px] font-black uppercase tracking-wider text-slate-500">
            {group.section}
          </p>
          <ul className="space-y-0.5">
            {group.items.map((item) => {
              const active = isActiveItem(pathname, item);
              return (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    className={`flex items-center gap-3 rounded-lg px-3 py-2 text-[13px] font-semibold transition-colors ${
                      active
                        ? "bg-natalo-500 text-white shadow-[0_4px_14px_rgba(30,95,191,0.4)]"
                        : "text-slate-300 hover:bg-white/5 hover:text-white"
                    }`}
                  >
                    <span className={active ? "text-white" : "text-slate-400"}>{item.icon}</span>
                    <span>{item.label}</span>
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </nav>
  );
}

function BrandHeader() {
  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo";
  return (
    <div className="flex items-center gap-2.5 border-b border-white/10 px-4 py-4">
      <div
        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-sm font-black text-white shadow-[0_6px_14px_rgba(30,95,191,0.4)]"
        style={{ background: "linear-gradient(135deg,#1E5FBF,#143E7E)" }}
      >
        N
      </div>
      <div className="leading-tight">
        <p className="text-sm font-extrabold text-white">{brand.split(" ")[0]}</p>
        <p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">Admin · CMS</p>
      </div>
    </div>
  );
}

function FooterUser() {
  return (
    <div className="border-t border-white/10 px-4 py-3">
      <LogoutButton
        redirectTo="/admin/login"
        className="w-full justify-center border-white/15 bg-white/5 text-slate-200 hover:border-white/30 hover:bg-white/10 hover:text-white"
      />
    </div>
  );
}

export function AdminNav({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen bg-slate-50">
      <aside className="fixed inset-y-0 left-0 z-30 flex w-60 flex-col bg-[#0c2a52]">
        <BrandHeader />
        <NavList />
        <FooterUser />
      </aside>

      <div className="flex min-w-0 flex-1 flex-col pl-60">
        <div className="flex-1">{children}</div>
      </div>
    </div>
  );
}
