"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  FiArrowLeft,
  FiBell,
  FiBookOpen,
  FiChevronDown,
  FiChevronRight,
  FiChevronUp,
  FiFileText,
  FiHelpCircle,
  FiInfo,
  FiLock,
  FiLogOut,
  FiMapPin,
  FiRefreshCw,
  FiShield,
  FiSliders,
  FiStar,
  FiTrash2,
  FiUser,
  FiVideo,
} from "react-icons/fi";
import type { IconType } from "react-icons";
import { BottomSheet } from "@/components/BottomSheet";
import { LogoutButton } from "@/components/LogoutButton";
import { natToast } from "@/components/Toast";

type SettingsItem = {
  href?: string;
  icon: IconType;
  title: string;
  subtitle: string;
  onClick?: () => void;
  trailing?: React.ReactNode;
  danger?: boolean;
  disabled?: boolean;
};

const AUTOPLAY_KEY = "account:settings:feedAutoplay";
const QUALITY_KEY = "account:settings:feedQuality";

const QUALITY_LABELS: Record<string, string> = {
  auto: "Otomatis",
  saver: "Hemat Data",
  high: "Tinggi",
};

export function AccountSettingsClient({ appVersion }: { appVersion: string }) {
  const [appSectionOpen, setAppSectionOpen] = useState(true);
  const [aboutSectionOpen, setAboutSectionOpen] = useState(true);
  const [autoplay, setAutoplay] = useState(true);
  const [quality, setQuality] = useState("auto");
  const [qualityOpen, setQualityOpen] = useState(false);
  const [cacheOpen, setCacheOpen] = useState(false);

  useEffect(() => {
    try {
      const autoplayValue = localStorage.getItem(AUTOPLAY_KEY);
      const qualityValue = localStorage.getItem(QUALITY_KEY);
      if (autoplayValue !== null) setAutoplay(autoplayValue === "1");
      if (qualityValue && QUALITY_LABELS[qualityValue]) setQuality(qualityValue);
    } catch {
      // Keep defaults if storage is unavailable.
    }
  }, []);

  function toggleAutoplay(next: boolean) {
    setAutoplay(next);
    try {
      localStorage.setItem(AUTOPLAY_KEY, next ? "1" : "0");
    } catch {
      // ignore
    }
  }

  function selectQuality(next: string) {
    setQuality(next);
    try {
      localStorage.setItem(QUALITY_KEY, next);
    } catch {
      // ignore
    }
    setQualityOpen(false);
    natToast(`Kualitas video: ${QUALITY_LABELS[next]}`, { kind: "ok" });
  }

  function clearCache() {
    try {
      const keysToRemove: string[] = [];
      for (let i = 0; i < localStorage.length; i += 1) {
        const key = localStorage.key(i);
        if (!key) continue;
        if (
          key.startsWith("feed:video-cache:") ||
          key.startsWith("image-cache:") ||
          key.startsWith("temporary-media:")
        ) {
          keysToRemove.push(key);
        }
      }
      keysToRemove.forEach((key) => localStorage.removeItem(key));
    } catch {
      // Cache cleanup is best-effort.
    }

    setCacheOpen(false);
    natToast("Cache berhasil dibersihkan", { kind: "ok" });
  }

  const accountItems = useMemo<SettingsItem[]>(
    () => [
      {
        href: "/account/profile",
        icon: FiUser,
        title: "Ubah Profil",
        subtitle: "Atur identitas dan foto profil kamu",
      },
      {
        href: "/akun/alamat",
        icon: FiMapPin,
        title: "Daftar Alamat",
        subtitle: "Kelola alamat pengiriman",
      },
      {
        href: "/akun/sesi-aktif",
        icon: FiLock,
        title: "Keamanan Akun",
        subtitle: "Kata sandi, PIN, dan sesi aktif",
      },
      {
        href: "/akun/pengaturan/notifikasi",
        icon: FiBell,
        title: "Notifikasi",
        subtitle: "Atur preferensi notifikasi aplikasi",
      },
      {
        href: "/kebijakan-privasi",
        icon: FiShield,
        title: "Privasi Akun",
        subtitle: "Pengaturan data dan privasi akun",
      },
    ],
    [],
  );

  const appItems = useMemo<SettingsItem[]>(
    () => [
      {
        icon: FiSliders,
        title: "Mode Tampilan",
        subtitle: "Terang, gelap, atau ikuti sistem",
        disabled: true,
        trailing: <span className="text-xs font-black text-slate-400">Segera</span>,
      },
      {
        icon: FiVideo,
        title: "Putar Otomatis Video",
        subtitle: "Putar video Feed secara otomatis",
        trailing: (
          <Switch
            checked={autoplay}
            onChange={toggleAutoplay}
            label="Putar otomatis video Feed"
          />
        ),
      },
      {
        icon: FiVideo,
        title: "Kualitas Video Feed",
        subtitle: "Atur kualitas video yang diputar",
        onClick: () => setQualityOpen(true),
        trailing: (
          <span className="text-xs font-black text-natalo-700">
            {QUALITY_LABELS[quality]}
          </span>
        ),
      },
      {
        icon: FiTrash2,
        title: "Bersihkan Cache",
        subtitle: "Hapus cache gambar dan video sementara",
        onClick: () => setCacheOpen(true),
        trailing: <span className="text-xs font-black text-slate-400">-</span>,
      },
    ],
    [autoplay, quality],
  );

  const aboutItems = useMemo<SettingsItem[]>(
    () => [
      {
        href: "/tentang-kami",
        icon: FiInfo,
        title: "Tentang Natalo",
        subtitle: "Kenali Natalo Petshop",
      },
      {
        href: "/bantuan",
        icon: FiHelpCircle,
        title: "Pusat Bantuan",
        subtitle: "FAQ, cara order, dan kontak toko",
      },
      {
        href: "/cara-pemesanan",
        icon: FiBookOpen,
        title: "Cara Pemesanan",
        subtitle: "Panduan order step-by-step",
      },
      {
        href: "/syarat-ketentuan",
        icon: FiFileText,
        title: "Syarat & Ketentuan",
        subtitle: "Ketentuan penggunaan layanan",
      },
      {
        href: "/kebijakan-privasi",
        icon: FiShield,
        title: "Kebijakan Privasi",
        subtitle: "Cara kami menjaga data kamu",
      },
      {
        href: "/kebijakan-pengembalian",
        icon: FiRefreshCw,
        title: "Kebijakan Pengembalian",
        subtitle: "Syarat retur dan refund",
      },
      {
        icon: FiStar,
        title: "Ulas Aplikasi Ini",
        subtitle: "Beri rating untuk Natalo",
        onClick: () => natToast("Fitur ulasan aplikasi akan segera tersedia", { kind: "ok" }),
      },
    ],
    [],
  );

  return (
    <main className="min-h-screen bg-[#F6F9FF] pb-[calc(2rem+env(safe-area-inset-bottom))]">
      <header className="sticky top-0 z-[1050] border-b border-slate-200/80 bg-white px-4 pb-3 shadow-[0_8px_24px_rgba(15,23,42,0.06)] [padding-top:calc(0.75rem+env(safe-area-inset-top))]">
        <div className="mx-auto flex max-w-2xl items-center gap-3">
          <Link
            href="/member"
            aria-label="Kembali ke akun"
            className="-ml-1 grid h-11 w-11 shrink-0 place-items-center rounded-full text-slate-800 transition active:bg-slate-100"
          >
            <FiArrowLeft className="h-5 w-5" aria-hidden="true" />
          </Link>
          <h1 className="min-w-0 flex-1 truncate text-xl font-black text-slate-950">
            Pengaturan
          </h1>
        </div>
      </header>

      <div className="mx-auto max-w-2xl space-y-5 px-4 py-5">
        <SettingsSection title="Akun">
          {accountItems.map((item) => (
            <SettingsListItem key={item.title} item={item} />
          ))}
        </SettingsSection>

        <SettingsSection
          title="Pengaturan Aplikasi"
          collapsible
          open={appSectionOpen}
          onToggle={() => setAppSectionOpen((open) => !open)}
        >
          {appItems.map((item) => (
            <SettingsListItem key={item.title} item={item} />
          ))}
        </SettingsSection>

        <SettingsSection
          title="Seputar Natalo"
          collapsible
          open={aboutSectionOpen}
          onToggle={() => setAboutSectionOpen((open) => !open)}
        >
          {aboutItems.map((item) => (
            <SettingsListItem key={item.title} item={item} />
          ))}
        </SettingsSection>

        <LogoutButton
          redirectTo="/member/login"
          confirmBeforeLogout
          className="flex w-full items-center gap-3 rounded-[20px] border border-red-100 bg-white p-4 text-left text-red-600 shadow-[0_8px_24px_rgba(16,24,40,0.06)] hover:border-red-200 hover:bg-red-50 hover:text-red-600"
        >
          <span className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-red-50 text-red-500">
            <FiLogOut className="h-5 w-5" aria-hidden="true" />
          </span>
          <span className="min-w-0 flex-1">
            <span className="block text-sm font-black">Keluar Akun</span>
            <span className="mt-0.5 block text-xs font-semibold text-red-400">
              Keluar dari akun Natalo di perangkat ini
            </span>
          </span>
          <FiChevronRight className="h-5 w-5 shrink-0 text-red-300" aria-hidden="true" />
        </LogoutButton>

        <p className="pb-2 text-center text-xs font-semibold text-slate-400">
          Versi {appVersion}
        </p>
      </div>

      <BottomSheet
        open={qualityOpen}
        onClose={() => setQualityOpen(false)}
        title="Kualitas Video Feed"
      >
        <div className="space-y-2">
          {Object.entries(QUALITY_LABELS).map(([value, label]) => (
            <button
              key={value}
              type="button"
              onClick={() => selectQuality(value)}
              className={`flex w-full items-center justify-between rounded-2xl px-4 py-3 text-left text-sm font-black transition active:bg-slate-50 ${
                quality === value ? "text-natalo-700" : "text-slate-800"
              }`}
            >
              {label}
              {quality === value && <span className="text-natalo-600">✓</span>}
            </button>
          ))}
        </div>
      </BottomSheet>

      <BottomSheet
        open={cacheOpen}
        onClose={() => setCacheOpen(false)}
        title="Bersihkan cache?"
        footer={
          <div className="grid grid-cols-2 gap-3">
            <button
              type="button"
              onClick={() => setCacheOpen(false)}
              className="h-11 rounded-full border border-slate-200 bg-white text-sm font-black text-slate-700 transition active:scale-[0.98]"
            >
              Batal
            </button>
            <button
              type="button"
              onClick={clearCache}
              className="h-11 rounded-full bg-natalo-600 text-sm font-black text-white transition active:scale-[0.98]"
            >
              Bersihkan
            </button>
          </div>
        }
      >
        <p className="text-sm font-semibold leading-6 text-slate-500">
          Cache gambar dan video sementara akan dihapus. Data akun, pesanan, dan wishlist kamu tetap aman.
        </p>
      </BottomSheet>
    </main>
  );
}

function SettingsSection({
  title,
  children,
  collapsible,
  open = true,
  onToggle,
}: {
  title: string;
  children: React.ReactNode;
  collapsible?: boolean;
  open?: boolean;
  onToggle?: () => void;
}) {
  const heading = (
    <>
      <span className="text-xs font-black uppercase tracking-[0.12em] text-natalo-600">
        {title}
      </span>
      {collapsible &&
        (open ? (
          <FiChevronUp className="h-4 w-4 text-slate-400" aria-hidden="true" />
        ) : (
          <FiChevronDown className="h-4 w-4 text-slate-400" aria-hidden="true" />
        ))}
    </>
  );

  return (
    <section>
      {collapsible ? (
        <button
          type="button"
          onClick={onToggle}
          className="mb-2 flex w-full items-center justify-between px-1 text-left"
        >
          {heading}
        </button>
      ) : (
        <div className="mb-2 flex w-full items-center justify-between px-1 text-left">
          {heading}
        </div>
      )}
      {open && (
        <div className="divide-y divide-slate-100 overflow-hidden rounded-[22px] border border-slate-100 bg-white shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
          {children}
        </div>
      )}
    </section>
  );
}

function SettingsListItem({ item }: { item: SettingsItem }) {
  const content = (
    <>
      <span
        className={`grid h-11 w-11 shrink-0 place-items-center rounded-2xl ${
          item.danger ? "bg-red-50 text-red-500" : "bg-[#EAF2FF] text-natalo-600"
        }`}
      >
        <item.icon className="h-5 w-5" aria-hidden="true" />
      </span>
      <span className="min-w-0 flex-1">
        <span
          className={`block text-sm font-black ${
            item.danger ? "text-red-600" : item.disabled ? "text-slate-400" : "text-slate-950"
          }`}
        >
          {item.title}
        </span>
        <span className="mt-0.5 block text-xs font-semibold leading-4 text-slate-500">
          {item.subtitle}
        </span>
      </span>
      {item.trailing}
      {!item.trailing && (item.href || item.onClick) && (
        <FiChevronRight className="h-5 w-5 shrink-0 text-slate-300" aria-hidden="true" />
      )}
    </>
  );

  const className =
    "flex min-h-[68px] w-full items-center gap-3 px-4 py-3 text-left transition";

  if (item.href && !item.disabled) {
    return (
      <Link href={item.href} className={`${className} active:bg-slate-50`}>
        {content}
      </Link>
    );
  }

  if (!item.onClick || item.disabled) {
    return (
      <div className={`${className} ${item.disabled ? "opacity-70" : ""}`}>
        {content}
      </div>
    );
  }

  return (
    <button
      type="button"
      onClick={item.onClick}
      className={`${className} active:bg-slate-50`}
    >
      {content}
    </button>
  );
}

function Switch({
  checked,
  onChange,
  label,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={(event) => {
        event.stopPropagation();
        onChange(!checked);
      }}
      className={`relative h-7 w-12 rounded-full transition ${
        checked ? "bg-natalo-600" : "bg-slate-200"
      }`}
    >
      <span
        className={`absolute top-1 h-5 w-5 rounded-full bg-white shadow-sm transition ${
          checked ? "left-6" : "left-1"
        }`}
      />
    </button>
  );
}
