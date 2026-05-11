"use client";

/**
 * Bottom sheet pemilihan voucher di halaman keranjang.
 *
 * 2 section:
 * 1. Voucher Member Natalo (sourceType=CUSTOMER) — list dari API
 *    /api/cart/vouchers, hanya untuk user login
 * 2. Kode Voucher Private (sourceType=SELLER_MANUAL) — input manual,
 *    di-validate via /api/cart/vouchers/validate-private
 *
 * Aturan kombinasi: maks 1 member + 1 private (single slot per tipe).
 *
 * Reuse CSS .voucher-* dari globals.css supaya konsisten dgn voucher
 * sheet di checkout. Keyboard handling pakai visualViewport +
 * @capacitor/keyboard untuk iOS native.
 */

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { formatRupiah } from "@/lib/format";

export type MemberVoucherItem = {
  id: string;
  code: string;
  description: string | null;
  minimumOrder: number;
  expiresAt: string | Date | null;
  discount: number;
  applicable: boolean;
  disabledReason: string | null;
};

type Props = {
  open: boolean;
  onClose: () => void;
  isLoggedIn: boolean;
  /** Subtotal cart yg dipakai untuk filter voucher applicable */
  subtotal: number;
  /** Voucher member terpilih saat ini */
  selectedMemberCode: string | null;
  /** Callback saat user pilih voucher member */
  onSelectMember: (
    code: string | null,
    discount: number,
    description: string,
  ) => void;
  /** Trigger redirect ke /login (kalau guest klik klaim) */
  onRequireLogin: () => void;
};

export function CartVoucherSheet({
  open,
  onClose,
  isLoggedIn,
  subtotal,
  selectedMemberCode,
  onSelectMember,
  onRequireLogin,
}: Props) {
  const [memberAvailable, setMemberAvailable] = useState<MemberVoucherItem[]>([]);
  const [memberUnavailable, setMemberUnavailable] = useState<MemberVoucherItem[]>([]);
  const [memberLoading, setMemberLoading] = useState(false);
  const [memberError, setMemberError] = useState("");

  // Lock body scroll + hide bottom-nav saat sheet open
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.body.classList.add("voucher-modal-open");
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      document.body.classList.remove("voucher-modal-open");
      document.removeEventListener("keydown", onKey);
    };
  }, [open, onClose]);

  // Keyboard inset detection — visualViewport (web) + Capacitor Keyboard (iOS native)
  useEffect(() => {
    if (!open) return;

    function updateInset() {
      const vp = window.visualViewport;
      const inset = vp
        ? Math.max(0, window.innerHeight - vp.height - vp.offsetTop)
        : 0;
      if (inset > 80) {
        document.documentElement.style.setProperty(
          "--nat-keyboard-inset",
          `${Math.round(inset)}px`,
        );
      } else {
        document.documentElement.style.removeProperty("--nat-keyboard-inset");
      }
    }

    updateInset();
    window.visualViewport?.addEventListener("resize", updateInset);
    window.visualViewport?.addEventListener("scroll", updateInset);

    let cleanupCap: (() => void) | null = null;
    (async () => {
      try {
        const { Keyboard } = await import("@capacitor/keyboard");
        const showH = await Keyboard.addListener("keyboardWillShow", (info) => {
          document.documentElement.style.setProperty(
            "--nat-keyboard-inset",
            `${Math.max(0, Math.round(info.keyboardHeight))}px`,
          );
        });
        const hideH = await Keyboard.addListener("keyboardWillHide", () => {
          document.documentElement.style.removeProperty("--nat-keyboard-inset");
        });
        cleanupCap = () => {
          showH.remove();
          hideH.remove();
        };
      } catch {
        // browser non-Capacitor: fallback visualViewport
      }
    })();

    return () => {
      window.visualViewport?.removeEventListener("resize", updateInset);
      window.visualViewport?.removeEventListener("scroll", updateInset);
      cleanupCap?.();
      document.documentElement.style.removeProperty("--nat-keyboard-inset");
    };
  }, [open]);

  // Fetch member vouchers saat sheet dibuka (kalau logged in)
  useEffect(() => {
    if (!open) return;
    if (!isLoggedIn) {
      setMemberAvailable([]);
      setMemberUnavailable([]);
      setMemberError("");
      return;
    }
    setMemberLoading(true);
    setMemberError("");
    fetch(`/api/cart/vouchers?subtotal=${subtotal}`)
      .then((r) => r.json().then((data) => ({ ok: r.ok, data })))
      .then(({ ok, data }) => {
        if (!ok) {
          setMemberError(data.message ?? "Gagal memuat voucher member");
          return;
        }
        setMemberAvailable(data.available ?? []);
        setMemberUnavailable(data.unavailable ?? []);
      })
      .catch(() => setMemberError("Gagal memuat voucher member"))
      .finally(() => setMemberLoading(false));
  }, [open, isLoggedIn, subtotal]);

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <>
      <div className="voucher-backdrop" onClick={onClose} />
      <div
        className="voucher-safe-area"
        role="dialog"
        aria-modal="true"
        aria-label="Pilih Voucher"
      >
        <div className="voucher-sheet">
          {/* Drag handle + header */}
          <div className="shrink-0 border-b border-zinc-100 bg-white">
            <div className="flex justify-center pt-2">
              <span className="block h-1 w-10 rounded-full bg-zinc-200" />
            </div>
            <div className="flex items-start justify-between gap-3 px-4 pb-3 pt-2">
              <div className="min-w-0">
                <h2 className="text-base font-extrabold text-zinc-950">Pilih Voucher</h2>
                <p className="mt-0.5 text-xs text-zinc-500">
                  Pilih voucher yang bisa dipakai untuk pesanan ini.
                </p>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-zinc-500 active:bg-zinc-100"
                aria-label="Tutup"
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5">
                  <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
                </svg>
              </button>
            </div>
          </div>

          {/* Konten scrollable */}
          <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4 [padding-bottom:calc(8px+env(safe-area-inset-bottom))]">
            {/* === Section 1: Voucher Member Natalo === */}
            <section>
              <div className="flex items-baseline justify-between">
                <h3 className="text-xs font-extrabold uppercase tracking-wide text-zinc-700">
                  Voucher Member Natalo
                </h3>
                {selectedMemberCode && (
                  <button
                    type="button"
                    onClick={() => onSelectMember(null, 0, "")}
                    className="text-[11px] font-bold text-natalo-600 active:underline"
                  >
                    Lepas
                  </button>
                )}
              </div>

              {!isLoggedIn ? (
                <div className="mt-2 rounded-xl border border-blue-100 bg-blue-50 p-3">
                  <p className="text-sm font-bold text-blue-900">Login dulu</p>
                  <p className="mt-1 text-xs text-blue-700">
                    Voucher member Natalo hanya untuk user yang sudah login.
                  </p>
                  <button
                    type="button"
                    onClick={onRequireLogin}
                    className="mt-3 w-full rounded-full bg-blue-600 px-4 py-2 text-sm font-bold text-white active:bg-blue-700"
                  >
                    Masuk / Daftar
                  </button>
                </div>
              ) : memberLoading ? (
                <p className="mt-2 text-xs text-zinc-500">Memuat voucher...</p>
              ) : memberError ? (
                <p className="mt-2 rounded-xl bg-red-50 px-3 py-2 text-xs font-semibold text-red-600">
                  {memberError}
                </p>
              ) : (
                <>
                  <p className="mt-1 text-[11px] font-bold uppercase tracking-wide text-emerald-700">
                    Bisa dipakai
                  </p>
                  {memberAvailable.length === 0 ? (
                    <p className="mt-1 rounded-xl bg-zinc-50 px-3 py-2 text-xs text-zinc-500">
                      Belum ada voucher yang bisa dipakai untuk pesanan ini.
                    </p>
                  ) : (
                    <ul className="mt-1 space-y-2">
                      {memberAvailable.map((v) => (
                        <li key={v.id}>
                          <MemberVoucherRow
                            voucher={v}
                            selected={selectedMemberCode === v.code}
                            disabled={false}
                            onSelect={() =>
                              onSelectMember(
                                v.code,
                                v.discount,
                                v.description ?? `Hemat ${formatRupiah(v.discount)}`,
                              )
                            }
                          />
                        </li>
                      ))}
                    </ul>
                  )}

                  {memberUnavailable.length > 0 && (
                    <>
                      <p className="mt-3 text-[11px] font-bold uppercase tracking-wide text-zinc-500">
                        Belum bisa dipakai
                      </p>
                      <ul className="mt-1 space-y-2">
                        {memberUnavailable.map((v) => (
                          <li key={v.id}>
                            <MemberVoucherRow
                              voucher={v}
                              selected={false}
                              disabled
                              onSelect={() => {}}
                            />
                          </li>
                        ))}
                      </ul>
                    </>
                  )}
                </>
              )}
            </section>
          </div>

          {/* Sticky footer — Terapkan */}
          <div className="sticky bottom-0 shrink-0 border-t border-zinc-100 bg-white px-4 pt-3 [padding-bottom:calc(12px+env(safe-area-inset-bottom))]">
            <button
              type="button"
              onClick={onClose}
              className="w-full rounded-2xl bg-natalo-600 px-4 py-3 text-sm font-black text-white transition active:bg-natalo-700"
            >
              Terapkan
            </button>
          </div>
        </div>
      </div>
    </>,
    document.body,
  );
}

function MemberVoucherRow({
  voucher,
  selected,
  disabled,
  onSelect,
}: {
  voucher: MemberVoucherItem;
  selected: boolean;
  disabled: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      type="button"
      onClick={disabled ? undefined : onSelect}
      disabled={disabled}
      aria-pressed={selected}
      className={`flex w-full items-stretch overflow-hidden rounded-xl border text-left transition ${
        disabled
          ? "cursor-not-allowed border-zinc-200 bg-zinc-50/60 opacity-70"
          : selected
          ? "border-natalo-400 bg-natalo-50 ring-1 ring-natalo-300"
          : "border-zinc-200 bg-white active:bg-zinc-50"
      }`}
    >
      <div className="flex flex-1 flex-col justify-center px-3 py-3">
        <p className={`text-sm font-extrabold ${disabled ? "text-zinc-500" : "text-zinc-950"}`}>
          {voucher.discount > 0
            ? `Hemat Rp${new Intl.NumberFormat("id-ID").format(voucher.discount)}`
            : "Voucher Member Natalo"}
        </p>
        <p className="mt-0.5 text-xs text-zinc-500">
          {voucher.minimumOrder > 0
            ? `Min. belanja Rp${new Intl.NumberFormat("id-ID").format(voucher.minimumOrder)}`
            : "Tanpa minimum belanja"}
        </p>
        <p className="mt-0.5 text-[11px] font-bold text-blue-700">Eksklusif member</p>
        {disabled && voucher.disabledReason && (
          <p className="mt-1 text-[11px] font-bold text-amber-700">
            {voucher.disabledReason}
          </p>
        )}
      </div>
      <div className={`flex shrink-0 items-center px-4 ${disabled ? "text-zinc-400" : "text-natalo-700"}`}>
        <span className="text-sm font-extrabold">
          {voucher.discount > 0
            ? `Rp${new Intl.NumberFormat("id-ID").format(voucher.discount)}`
            : "—"}
        </span>
      </div>
    </button>
  );
}
