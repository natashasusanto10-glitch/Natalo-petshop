"use client";

import { useEffect, useState } from "react";
import { isCapacitorNative } from "@/lib/native-platform";

/**
 * App Store badge — promote download Natalo Petshop iOS app dari App Store.
 *
 * Auto-hide kalau sudah jalan di Capacitor native shell (user yang lagi
 * pakai app iOS tidak perlu di-promote untuk download app — redundant + bingung).
 * Render di:
 * - Web (Vercel) — visible untuk semua user yang akses lewat browser
 * - PWA (Add to Home Screen) — visible (PWA bukan native, beda dengan iOS app)
 * - Hidden di Capacitor iOS (.ipa) — user sudah punya app
 *
 * Variant:
 * - "default": badge hitam standar Apple style, untuk light bg
 * - "compact": versi lebih kecil, untuk space terbatas
 * - "outlined": versi outline putih untuk dark bg
 *
 * App ID 6767888044 dari App Store Connect.
 */

const APP_STORE_URL = "https://apps.apple.com/id/app/natalo-petshop/id6767888044";

type Variant = "default" | "compact" | "outlined";

interface AppStoreBadgeProps {
  variant?: Variant;
  className?: string;
}

/**
 * Apple logo SVG path — sourced dari Apple's marketing guidelines.
 */
function AppleLogo({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="currentColor"
      className={className}
      aria-hidden="true"
    >
      <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09l.01-.01zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
    </svg>
  );
}

function BadgeContent({ variant }: { variant: Variant }) {
  if (variant === "compact") {
    return (
      <>
        <AppleLogo className="h-5 w-5" />
        <span className="text-sm font-bold leading-none">App Store</span>
      </>
    );
  }

  return (
    <>
      <AppleLogo className="h-7 w-7" />
      <div className="flex flex-col items-start leading-tight">
        <span className="text-[10px] font-medium uppercase tracking-wide opacity-90">
          Download di
        </span>
        <span className="text-base font-black leading-none">App Store</span>
      </div>
    </>
  );
}

export function AppStoreBadge({
  variant = "default",
  className = "",
}: AppStoreBadgeProps) {
  // Hide inside Capacitor native shell — user sudah punya app
  const [isNative, setIsNative] = useState<boolean | null>(null);

  useEffect(() => {
    setIsNative(isCapacitorNative());
  }, []);

  // Initial render (SSR + client first paint): show badge (default behavior)
  // Setelah client-side check: hide kalau native
  if (isNative === true) return null;

  const baseClass =
    "inline-flex items-center gap-2.5 rounded-xl transition active:scale-95 active:opacity-90";

  const variantClass =
    variant === "outlined"
      ? "border-2 border-white bg-transparent px-4 py-2.5 text-white hover:bg-white/10"
      : variant === "compact"
        ? "bg-zinc-950 px-3 py-2 text-white hover:bg-zinc-800"
        : "bg-zinc-950 px-5 py-2.5 text-white shadow-md hover:bg-zinc-800";

  return (
    <a
      href={APP_STORE_URL}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="Download Natalo Petshop di App Store"
      className={`${baseClass} ${variantClass} ${className}`}
    >
      <BadgeContent variant={variant} />
    </a>
  );
}

/**
 * Full hero CTA card — large promotional banner untuk highlight app launch
 * di homepage. Brand-blue gradient bg dengan iPhone mockup vibe.
 */
export function AppStoreCTACard({ className = "" }: { className?: string }) {
  const [isNative, setIsNative] = useState<boolean | null>(null);

  useEffect(() => {
    setIsNative(isCapacitorNative());
  }, []);

  if (isNative === true) return null;

  return (
    <div
      className={`relative overflow-hidden rounded-3xl bg-gradient-to-br from-natalo-700 via-natalo-600 to-natalo-800 px-5 py-6 shadow-lg sm:px-7 sm:py-8 ${className}`}
    >
      {/* Decorative paw pattern background */}
      <div
        className="pointer-events-none absolute inset-0 opacity-10"
        aria-hidden="true"
      >
        <svg className="absolute -right-6 -top-6 h-32 w-32 text-white" viewBox="0 0 24 24" fill="currentColor">
          <path d="M8 20c-2 0-3-1.2-3-2.7 0-2.4 3.1-4.8 7-4.8s7 2.4 7 4.8c0 1.5-1 2.7-3 2.7-1.4 0-2.5-.8-4-.8s-2.6.8-4 .8Z" />
          <circle cx="6.5" cy="10" r="1.8" />
          <circle cx="10" cy="7" r="1.8" />
          <circle cx="14" cy="7" r="1.8" />
          <circle cx="17.5" cy="10" r="1.8" />
        </svg>
        <svg className="absolute -bottom-4 -left-4 h-24 w-24 rotate-12 text-white" viewBox="0 0 24 24" fill="currentColor">
          <path d="M8 20c-2 0-3-1.2-3-2.7 0-2.4 3.1-4.8 7-4.8s7 2.4 7 4.8c0 1.5-1 2.7-3 2.7-1.4 0-2.5-.8-4-.8s-2.6.8-4 .8Z" />
          <circle cx="6.5" cy="10" r="1.8" />
          <circle cx="10" cy="7" r="1.8" />
          <circle cx="14" cy="7" r="1.8" />
          <circle cx="17.5" cy="10" r="1.8" />
        </svg>
      </div>

      <div className="relative flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex-1">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-white/20 px-2.5 py-1 text-[10px] font-black uppercase tracking-wide text-white backdrop-blur">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-300" />
            Baru di App Store
          </span>
          <h3 className="mt-2.5 text-lg font-black leading-tight text-white sm:text-xl">
            Belanja di app native iPhone
          </h3>
          <p className="mt-1 max-w-md text-xs leading-relaxed text-white/90 sm:text-sm">
            Push notification real-time, tracking pesanan, dan loyalty point.
            Download Natalo Petshop di App Store sekarang.
          </p>
        </div>

        <div className="shrink-0">
          {/* Override default badge styling: white bg with dark text on the
              brand-blue gradient card. Pakai ! prefix supaya menang specificity
              dari variantClass base "bg-zinc-950 text-white". */}
          <AppStoreBadge
            variant="default"
            className="!bg-white !text-zinc-950 hover:!bg-zinc-100"
          />
        </div>
      </div>
    </div>
  );
}
