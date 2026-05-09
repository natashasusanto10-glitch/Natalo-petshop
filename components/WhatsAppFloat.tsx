"use client";

import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

const PHONE =
  process.env.NEXT_PUBLIC_WA_NUMBER ??
  process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ??
  "";

const BRAND = process.env.NEXT_PUBLIC_BRAND_NAME ?? "Petshop";
const DEFAULT_MESSAGE = `Halo ${BRAND}, saya mau tanya tentang produk.`;

/**
 * Floating WhatsApp button — muncul di pojok kanan bawah semua halaman customer.
 * Hide otomatis di:
 *   - /admin/* (admin tidak butuh)
 *   - /checkout (jangan ganggu user yang lagi bayar)
 *   - /member/login, /register, /forgot-password (page minimal, no distraction)
 */
export function WhatsAppFloat() {
  const pathname = usePathname();
  const [showTooltip, setShowTooltip] = useState(false);
  const [tooltipDismissed, setTooltipDismissed] = useState(false);

  // Auto-show tooltip setelah 3 detik (sekali per session)
  useEffect(() => {
    if (typeof window === "undefined") return;
    const dismissed = sessionStorage.getItem("wa-tooltip-dismissed") === "1";
    if (dismissed) {
      setTooltipDismissed(true);
      return;
    }
    const t = setTimeout(() => setShowTooltip(true), 3000);
    return () => clearTimeout(t);
  }, [pathname]);

  function dismissTooltip() {
    setShowTooltip(false);
    setTooltipDismissed(true);
    sessionStorage.setItem("wa-tooltip-dismissed", "1");
  }

  // Hide di route tertentu (cart & PDP punya CTA bottom-bar yang akan overlap)
  const hideOn = [
    "/admin",
    "/checkout",
    "/cart",
    "/member/login",
    "/member/register",
    "/member/forgot-password",
    "/member/reset-password",
  ];
  const shouldHide =
    hideOn.some((p) => pathname === p || pathname.startsWith(`${p}/`)) ||
    pathname.startsWith("/products/"); // PDP punya WA button + sticky CTA

  if (shouldHide || !PHONE) return null;

  const href = `https://wa.me/${PHONE.replace(/^\+/, "")}?text=${encodeURIComponent(DEFAULT_MESSAGE)}`;

  return (
    <div className="nat-whatsapp-float fixed z-40 flex flex-col items-end gap-2">
      {/* Tooltip popup */}
      {showTooltip && !tooltipDismissed && (
        <div className="relative max-w-[260px] rounded-2xl bg-white px-4 py-3 shadow-xl ring-1 ring-zinc-200 animate-in slide-in-from-bottom-2 fade-in duration-300">
          <button
            type="button"
            onClick={dismissTooltip}
            aria-label="Tutup"
            className="absolute -right-2 -top-2 flex h-6 w-6 items-center justify-center rounded-full bg-zinc-200 text-xs text-zinc-600 hover:bg-zinc-300"
          >
            ✕
          </button>
          <p className="text-sm font-bold text-zinc-950">
            Hai! Ada yang bisa kami bantu? 👋
          </p>
          <p className="mt-1 text-xs text-zinc-500">
            Chat via WhatsApp — fast response.
          </p>
          {/* Speech bubble tail */}
          <div
            className="absolute -bottom-2 right-6 h-3 w-3 rotate-45 bg-white"
            style={{ boxShadow: "1px 1px 0 0 rgb(228, 228, 231)" }}
          />
        </div>
      )}

      {/* Main button */}
      <a
        href={href}
        target="_blank"
        rel="noreferrer noopener"
        aria-label="Chat via WhatsApp"
        onClick={dismissTooltip}
        className="group relative flex h-14 w-14 items-center justify-center rounded-full bg-[#25D366] text-white shadow-lg transition hover:scale-110 hover:bg-[#1ebe57] hover:shadow-xl active:scale-95"
        style={{
          boxShadow: "0 4px 14px rgba(37, 211, 102, 0.4)",
        }}
      >
        {/* Pulse ring animation */}
        <span className="absolute inset-0 rounded-full bg-[#25D366] opacity-75 group-hover:animate-none animate-ping-slow" />

        {/* WhatsApp icon */}
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          className="relative h-7 w-7"
          aria-hidden="true"
        >
          <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z" />
        </svg>
      </a>

      {/* Custom keyframe — slow pulse */}
      <style jsx>{`
        @keyframes pingSlow {
          0% {
            transform: scale(1);
            opacity: 0.5;
          }
          75%,
          100% {
            transform: scale(1.4);
            opacity: 0;
          }
        }
        .animate-ping-slow {
          animation: pingSlow 2s cubic-bezier(0, 0, 0.2, 1) infinite;
        }
      `}</style>
    </div>
  );
}
