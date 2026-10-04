"use client";

import { useEffect, useState, useCallback, type ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { LogoutButton } from "./LogoutButton";
import { AdminContentMotion } from "./admin/ui/Motion";
import { AdminDialog } from "./admin/ui/AdminDialog";

type NavItem = {
  href: string;
  label: string;
  icon: ReactNode;
  exact?: boolean;
};
type NavGroup = { section: string; items: NavItem[] };

const NAV_GROUPS: NavGroup[] = [
  {
    section: "Operasi",
    items: [
      {
        href: "/admin/dashboard",
        label: "Ringkasan",
        exact: true,
        icon: <Glyph d="M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z" />,
      },
      {
        href: "/admin/orders",
        label: "Pesanan",
        icon: (
          <Glyph d="M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 3h6v4H9zM9 12h6M9 16h4" />
        ),
      },
      {
        href: "/admin/pickup-validation",
        label: "Validasi Pickup",
        icon: (
          <Glyph d="M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
        ),
      },
      {
        href: "/admin/products",
        label: "Produk",
        icon: (
          <Glyph d="M20 7H4a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1V8a1 1 0 0 0-1-1ZM16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2" />
        ),
      },
      {
        href: "/admin/categories",
        label: "Kategori",
        icon: <Glyph d="M3 6h18M3 12h18M3 18h18" />,
      },
      {
        href: "/admin/stock",
        label: "Pantau stok",
        icon: (
          <Glyph d="M5 8h14M3 8a2 2 0 1 1 4 0v12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2V8a2 2 0 1 1 4 0M9 8V6a2 2 0 1 1 4 0v2m4 0V6a2 2 0 1 1 4 0v2" />
        ),
      },
    ],
  },
  {
    section: "Marketing",
    items: [
      {
        // Hub Buat Diskon — landing untuk semua jenis promosi:
        // Promo Toko (diskon per-produk) + Voucher + Flash Sale + Paket.
        // Sebelumnya nav langsung ke /admin/vouchers (1 modul), sekarang
        // ke /admin/diskon (hub yang grouping semua + link ke vouchers).
        href: "/admin/diskon",
        label: "Promo Toko",
        icon: (
          <Glyph d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82zM7 7h.01" />
        ),
      },
      {
        href: "/admin/brands",
        label: "Brand",
        icon: (
          <Glyph d="M12 2 2 7l10 5 10-5-10-5ZM2 17l10 5 10-5M2 12l10 5 10-5" />
        ),
      },
      {
        href: "/admin/banners",
        label: "Banner Beranda",
        icon: (
          <Glyph d="M3 5h18a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1ZM3 15l5-5 4 4 3-3 6 6" />
        ),
      },
      {
        href: "/admin/launch-popup",
        label: "Popup Promo",
        icon: (
          <Glyph d="M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm3 15h4" />
        ),
      },
      {
        href: "/admin/broadcast",
        label: "Broadcast Notifikasi",
        icon: <Glyph d="M3 11l18-8-5 18-4-9-9-1zM13 12l8-9" />,
      },
      {
        href: "/admin/feed",
        label: "Feed",
        icon: (
          <Glyph d="M23 7l-7 5 7 5V7zM14 5H3a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2z" />
        ),
      },
      {
        href: "/admin/feed/reports",
        label: "Moderasi Laporan",
        icon: (
          <Glyph d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1v18" />
        ),
      },
    ],
  },
  {
    section: "Pelanggan",
    items: [
      {
        href: "/admin/customers",
        label: "Pelanggan",
        icon: (
          <Glyph d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" />
        ),
      },
      {
        href: "/admin/reviews",
        label: "Ulasan",
        icon: (
          <Glyph d="m12 2 3.09 6.26L22 9.27l-5 4.87L18.18 21 12 17.77 5.82 21 7 14.14 2 9.27l6.91-1.01L12 2Z" />
        ),
      },
      {
        href: "/admin/abuse-flags",
        label: "Indikasi penyalahgunaan",
        icon: <Glyph d="M4 22V4a1 1 0 0 1 1-1h13l-2.5 4.5L18 12H5M12 22v-4" />,
      },
      {
        // CS tool: override tgl lahir customer yang ke-lock setelah dapat
        // voucher ultah. Anti-abuse lock di sistem otomatis, tapi genuine
        // cases (salah input) butuh manual override dengan audit log.
        href: "/admin/birth-date-overrides",
        label: "Koreksi tanggal lahir",
        icon: <Glyph d="M12 8v4l3 3M3 12a9 9 0 1 0 18 0 9 9 0 0 0-18 0z" />,
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
        href: "/admin/audit-log",
        label: "Riwayat aktivitas",
        icon: (
          <Glyph d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6M9 13h6M9 17h4" />
        ),
      },
      {
        href: "/admin/settings",
        label: "Pengaturan",
        icon: (
          <Glyph d="M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82 1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z" />
        ),
      },
    ],
  },
];

const PREMIUM_NAV_GROUPS = [
  {
    section: "Workspace",
    hrefs: ["/admin/dashboard", "/admin/orders", "/admin/pickup-validation"],
  },
  {
    section: "Katalog",
    hrefs: [
      "/admin/products",
      "/admin/categories",
      "/admin/brands",
      "/admin/stock",
    ],
  },
  {
    section: "Promosi & konten",
    hrefs: [
      "/admin/diskon",
      "/admin/banners",
      "/admin/launch-popup",
      "/admin/broadcast",
      "/admin/feed",
      "/admin/feed/reports",
    ],
  },
  {
    section: "Pelanggan",
    hrefs: [
      "/admin/customers",
      "/admin/reviews",
      "/admin/birth-date-overrides",
    ],
  },
  {
    section: "Pengelolaan",
    hrefs: [
      "/admin/reports",
      "/admin/settings",
      "/admin/audit-log",
      "/admin/abuse-flags",
    ],
  },
].map((group) => ({
  section: group.section,
  items: group.hrefs
    .map(
      (href) =>
        NAV_GROUPS.flatMap((g) => g.items).find((item) => item.href === href)!
    )
    .filter(Boolean),
}));

const MOBILE_PRIMARY_HREFS = [
  "/admin/dashboard",
  "/admin/orders",
  "/admin/products",
  "/admin/diskon",
];

function Glyph({ d }: { d: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-[18px] w-[18px]"
    >
      <path d={d} />
    </svg>
  );
}

function matchesItem(pathname: string, item: NavItem) {
  if (item.exact) return pathname === item.href;
  return pathname === item.href || pathname.startsWith(`${item.href}/`);
}

/** Cari nav item paling spesifik (href terpanjang) yang match pathname —
 * mencegah dua item sama-sama menyala saat satu href adalah prefix dari
 * yang lain (mis. "/admin/feed" vs "/admin/feed/reports"). */
function findActiveItem(pathname: string): NavItem | null {
  let best: NavItem | null = null;
  for (const group of NAV_GROUPS) {
    for (const item of group.items) {
      if (!matchesItem(pathname, item)) continue;
      if (!best || item.href.length > best.href.length) best = item;
    }
  }
  return best;
}

function isActiveItem(pathname: string, item: NavItem) {
  return findActiveItem(pathname)?.href === item.href;
}

function titleCaseSegment(segment: string): string {
  return segment
    .split("-")
    .map((word) => (word ? word[0].toUpperCase() + word.slice(1) : word))
    .join(" ");
}

function getPageTitle(pathname: string): string {
  for (const group of NAV_GROUPS) {
    for (const item of group.items) {
      if (isActiveItem(pathname, item)) return item.label;
    }
  }
  const segments = pathname.split("/").filter(Boolean);
  const last = segments[segments.length - 1];
  return last ? titleCaseSegment(last) : "Admin";
}

function NavList({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();

  return (
    <nav className="flex-1 overflow-y-auto px-3 pb-4">
      {PREMIUM_NAV_GROUPS.map((group) => (
        <div key={group.section} className="mt-1">
          <p className="px-3 pb-1.5 pt-3 text-xs font-semibold uppercase tracking-wider text-slate-500">
            {group.section}
          </p>
          <ul className="space-y-0.5">
            {group.items.map((item) => {
              const active = isActiveItem(pathname, item);
              return (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    aria-current={active ? "page" : undefined}
                    onClick={onNavigate}
                    className={`flex items-center gap-3 rounded-lg px-3 py-2.5 text-[13px] font-semibold transition-colors ${
                      active
                        ? "bg-[#edf3ff] text-[#245bd6]"
                        : "text-slate-600 hover:bg-slate-50 hover:text-slate-950"
                    }`}
                  >
                    <span
                      className={active ? "text-[#245bd6]" : "text-slate-500"}
                    >
                      {item.icon}
                    </span>
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
    <div className="flex items-center gap-2.5 border-b border-slate-100 px-4 py-4">
      <div
        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-sm font-black text-white shadow-[0_6px_14px_rgba(30,95,191,0.4)]"
        style={{ background: "linear-gradient(135deg,#1E5FBF,#143E7E)" }}
      >
        N
      </div>
      <div className="leading-tight">
        <p className="text-xl font-semibold text-slate-950">
          {brand.split(" ")[0]}
        </p>
        <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
          Admin · CMS
        </p>
      </div>
    </div>
  );
}

function FooterUser() {
  return (
    <div className="border-t border-slate-100 px-4 py-3">
      <LogoutButton
        redirectTo="/admin/login"
        className="w-full justify-center border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
      />
    </div>
  );
}

function MobileTopBar({
  title,
  onMenuClick,
}: {
  title: string;
  onMenuClick: () => void;
}) {
  return (
    <header className="sticky top-0 z-30 flex h-[73px] items-center gap-3 border-b border-slate-200 bg-white px-4 md:px-8">
      <div
        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-xs font-black text-white"
        style={{ background: "linear-gradient(135deg,#1E5FBF,#143E7E)" }}
      >
        N
      </div>
      <div className="flex-1 text-sm font-semibold text-slate-800">
        <span className="mr-3 hidden font-normal text-slate-500 md:inline">
          Workspace /
        </span>
        {title}
      </div>
      <button
        type="button"
        onClick={onMenuClick}
        aria-label="Buka menu"
        className="inline-flex h-11 w-11 items-center justify-center rounded-md text-slate-700 hover:bg-slate-100 md:hidden"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
          className="h-5 w-5"
        >
          <path d="M3 6h18M3 12h18M3 18h18" />
        </svg>
      </button>
    </header>
  );
}

function MobileBottomNav({ onMoreClick }: { onMoreClick: () => void }) {
  const pathname = usePathname();
  const primaryItems = MOBILE_PRIMARY_HREFS.map((href) =>
    NAV_GROUPS.flatMap((g) => g.items).find((i) => i.href === href)
  ).filter((i): i is NavItem => Boolean(i));

  return (
    <nav
      className="fixed inset-x-0 bottom-0 z-30 flex h-[calc(66px+env(safe-area-inset-bottom))] border-t border-slate-200 bg-white pb-[env(safe-area-inset-bottom)] md:hidden"
      aria-label="Navigasi utama"
    >
      {primaryItems.map((item) => {
        const active = isActiveItem(pathname, item);
        return (
          <Link
            key={item.href}
            href={item.href}
            className={`flex flex-1 flex-col items-center justify-center gap-0.5 py-2 text-xs font-semibold transition-colors ${
              active ? "text-natalo-500" : "text-slate-500"
            }`}
          >
            <span className={active ? "text-natalo-500" : "text-slate-500"}>
              {item.icon}
            </span>
            <span className="leading-tight">{item.label}</span>
          </Link>
        );
      })}
      <button
        type="button"
        onClick={onMoreClick}
        className="flex flex-1 flex-col items-center justify-center gap-0.5 py-2 text-xs font-semibold text-slate-500"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={1.8}
          strokeLinecap="round"
          strokeLinejoin="round"
          className="h-[18px] w-[18px]"
        >
          <circle cx="5" cy="12" r="1.5" />
          <circle cx="12" cy="12" r="1.5" />
          <circle cx="19" cy="12" r="1.5" />
        </svg>
        <span className="leading-tight">Lainnya</span>
      </button>
    </nav>
  );
}

function MobileDrawer({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  return (
    <AdminDialog
      open={open}
      title="Menu"
      onClose={onClose}
      side
      className="admin-navigation-dialog"
    >
      <NavList onNavigate={onClose} />
      <FooterUser />
    </AdminDialog>
  );
}

export function AdminNav({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const title = getPageTitle(pathname);
  const closeDrawer = useCallback(() => setDrawerOpen(false), []);

  useEffect(() => {
    setDrawerOpen(false);
  }, [pathname]);

  useEffect(() => {
    const desktop = window.matchMedia("(min-width: 768px)");
    const resize = () => {
      if (desktop.matches) setDrawerOpen(false);
    };
    desktop.addEventListener("change", resize);
    return () => desktop.removeEventListener("change", resize);
  }, []);

  return (
    <div data-admin-workspace className="flex min-h-screen">
      <a
        href="#admin-main-content"
        className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[100] focus:rounded-lg focus:bg-white focus:p-3"
      >
        Lewati ke konten
      </a>
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col border-r border-slate-200 bg-white md:flex">
        <BrandHeader />
        <NavList />
        <FooterUser />
      </aside>

      <div className="flex min-w-0 flex-1 flex-col md:pl-60">
        <MobileTopBar title={title} onMenuClick={() => setDrawerOpen(true)} />
        <div
          id="admin-main-content"
          className="flex-1 pb-[calc(66px+env(safe-area-inset-bottom))] md:pb-0"
        >
          <AdminContentMotion>{children}</AdminContentMotion>
        </div>
      </div>

      <MobileBottomNav onMoreClick={() => setDrawerOpen(true)} />
      <MobileDrawer open={drawerOpen} onClose={closeDrawer} />
    </div>
  );
}
