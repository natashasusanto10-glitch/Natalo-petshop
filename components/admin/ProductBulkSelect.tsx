"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import { useAdminToast } from "@/components/admin/ui/Toast";

/**
 * Seleksi massal produk untuk halaman /admin/products.
 *
 * Pola: server component me-render daftar produk; provider client ini
 * membungkusnya dan menyimpan Set id terpilih. Tiap baris punya
 * <ProductRowCheckbox>, header punya <ProductSelectAll>, dan
 * <ProductBulkBar> muncul mengambang saat ada yang dicentang untuk
 * Hapus / Arsipkan massal via POST /api/admin/products/bulk.
 */

type SelectionCtx = {
  isSelected: (id: string) => boolean;
  toggle: (id: string) => void;
  selectedIds: string[];
  count: number;
  allSelected: boolean;
  someSelected: boolean;
  toggleAll: () => void;
  clear: () => void;
};

const Ctx = createContext<SelectionCtx | null>(null);

function useSelection(): SelectionCtx {
  const ctx = useContext(Ctx);
  if (!ctx) {
    throw new Error("Komponen seleksi harus di dalam <ProductSelectionProvider>");
  }
  return ctx;
}

const CHECKBOX_CLS =
  "h-[18px] w-[18px] shrink-0 cursor-pointer rounded border-zinc-300 accent-natalo-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-natalo-500/50";

export function ProductSelectionProvider({
  allIds,
  children,
}: {
  allIds: string[];
  children: ReactNode;
}) {
  const [selected, setSelected] = useState<Set<string>>(() => new Set());

  // Setelah hapus/refresh atau ganti filter, buang id terpilih yang sudah
  // tidak ada di halaman ini supaya bar tidak menghitung id basi.
  useEffect(() => {
    const present = new Set(allIds);
    setSelected((prev) => {
      let changed = false;
      const next = new Set<string>();
      for (const id of prev) {
        if (present.has(id)) next.add(id);
        else changed = true;
      }
      return changed ? next : prev;
    });
  }, [allIds]);

  const value = useMemo<SelectionCtx>(() => {
    const allSelected = allIds.length > 0 && allIds.every((id) => selected.has(id));
    return {
      isSelected: (id) => selected.has(id),
      toggle: (id) =>
        setSelected((prev) => {
          const next = new Set(prev);
          if (next.has(id)) next.delete(id);
          else next.add(id);
          return next;
        }),
      selectedIds: [...selected],
      count: selected.size,
      allSelected,
      someSelected: selected.size > 0 && !allSelected,
      toggleAll: () =>
        setSelected((prev) => {
          const all = allIds.length > 0 && allIds.every((id) => prev.has(id));
          return all ? new Set() : new Set(allIds);
        }),
      clear: () => setSelected(new Set()),
    };
  }, [selected, allIds]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function ProductRowCheckbox({ id }: { id: string }) {
  const { isSelected, toggle } = useSelection();
  return (
    <input
      type="checkbox"
      checked={isSelected(id)}
      onChange={() => toggle(id)}
      aria-label="Pilih produk ini"
      className={CHECKBOX_CLS}
    />
  );
}

export function ProductSelectAll() {
  const { allSelected, someSelected, toggleAll } = useSelection();
  const ref = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (ref.current) ref.current.indeterminate = someSelected;
  }, [someSelected]);
  return (
    <input
      ref={ref}
      type="checkbox"
      checked={allSelected}
      onChange={toggleAll}
      aria-label="Pilih semua produk di halaman ini"
      className={CHECKBOX_CLS}
    />
  );
}

type ActionResult = { deleted: number; archived: number; failed: number };

export function ProductBulkBar() {
  const { count, selectedIds, clear } = useSelection();
  const router = useRouter();
  const [confirmAction, setConfirmAction] = useState<null | "delete" | "archive">(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { show } = useAdminToast();

  // Tutup dialog + reset error kalau tidak ada lagi yang terpilih.
  useEffect(() => {
    if (count === 0) {
      setConfirmAction(null);
      setError(null);
    }
  }, [count]);

  async function run(action: "delete" | "archive") {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/admin/products/bulk", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ids: selectedIds, action }),
      });
      const data: (ActionResult & { error?: string }) | null = await res
        .json()
        .catch(() => null);
      if (!res.ok) throw new Error(data?.error || "Gagal memproses. Coba lagi.");

      setConfirmAction(null);
      clear();
      if (action === "delete") {
        const parts = [`${data?.deleted ?? 0} dihapus`];
        if (data?.archived) parts.push(`${data.archived} diarsipkan (pernah dipesan)`);
        if (data?.failed) parts.push(`${data.failed} gagal`);
        show(parts.join(" · "));
      } else {
        show(`${data?.archived ?? 0} produk diarsipkan`);
      }
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memproses.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      {/* Bar aksi mengambang */}
      {count > 0 && (
        <div className="pointer-events-none fixed inset-x-0 bottom-[calc(4.75rem+env(safe-area-inset-bottom))] z-40 flex justify-center px-4 md:bottom-6">
          <div className="pointer-events-auto flex w-full max-w-xl items-center gap-2 rounded-2xl border border-white/10 bg-zinc-950 px-2.5 py-2 shadow-[0_16px_48px_-12px_rgba(0,0,0,0.55)] md:gap-3 md:px-3">
            <button
              type="button"
              onClick={clear}
              aria-label="Batalkan pilihan"
              className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-zinc-400 transition hover:bg-white/10 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/40"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className="h-5 w-5" aria-hidden="true">
                <path d="M18 6 6 18M6 6l12 12" />
              </svg>
            </button>
            <span className="text-sm font-bold text-white">
              <span className="tabular-nums">{count}</span> dipilih
            </span>
            <div className="ml-auto flex items-center gap-2">
              <button
                type="button"
                onClick={() => setConfirmAction("archive")}
                className="inline-flex h-11 items-center gap-1.5 rounded-full border border-white/20 bg-white/5 px-4 text-sm font-bold text-white transition hover:bg-white/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/40"
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round" className="h-[17px] w-[17px]" aria-hidden="true">
                  <path d="M21 8v13H3V8M1 3h22v5H1zM10 12h4" />
                </svg>
                Arsipkan
              </button>
              <button
                type="button"
                onClick={() => setConfirmAction("delete")}
                className="inline-flex h-11 items-center gap-1.5 rounded-full bg-red-600 px-4 text-sm font-bold text-white transition hover:bg-red-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-400"
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round" className="h-[17px] w-[17px]" aria-hidden="true">
                  <path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
                </svg>
                Hapus
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Dialog konfirmasi */}
      {confirmAction && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="bulk-confirm-title"
          className="fixed inset-0 z-[60] flex items-end justify-center bg-black/50 p-4 sm:items-center"
          onClick={() => !busy && setConfirmAction(null)}
        >
          <div
            className="w-full max-w-sm rounded-3xl bg-white p-5 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start gap-3">
              <div
                className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-full ${
                  confirmAction === "delete" ? "bg-red-100 text-red-600" : "bg-amber-100 text-amber-600"
                }`}
              >
                {confirmAction === "delete" ? (
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round" className="h-5 w-5" aria-hidden="true">
                    <path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
                  </svg>
                ) : (
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round" className="h-5 w-5" aria-hidden="true">
                    <path d="M21 8v13H3V8M1 3h22v5H1zM10 12h4" />
                  </svg>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <h2 id="bulk-confirm-title" className="text-base font-black text-zinc-950">
                  {confirmAction === "delete"
                    ? `Hapus ${count} produk?`
                    : `Arsipkan ${count} produk?`}
                </h2>
                <p className="mt-1.5 text-sm leading-relaxed text-zinc-600">
                  {confirmAction === "delete" ? (
                    <>
                      Produk yang belum pernah dipesan akan{" "}
                      <span className="font-bold text-zinc-900">dihapus permanen</span> dan tidak bisa
                      dikembalikan. Produk yang pernah dipesan otomatis{" "}
                      <span className="font-bold text-zinc-900">diarsipkan</span>.
                    </>
                  ) : (
                    <>
                      Produk disembunyikan dari toko. Kamu bisa memulihkannya kapan saja lewat tab{" "}
                      <span className="font-bold text-zinc-900">Arsip</span>.
                    </>
                  )}
                </p>
              </div>
            </div>

            {error && (
              <p className="mt-4 rounded-xl bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">
                {error}
              </p>
            )}

            <div className="mt-5 flex gap-2.5">
              <button
                type="button"
                onClick={() => setConfirmAction(null)}
                disabled={busy}
                className="h-11 flex-1 rounded-full border border-zinc-300 text-sm font-bold text-zinc-700 transition hover:bg-zinc-50 disabled:opacity-50"
              >
                Batal
              </button>
              <button
                type="button"
                onClick={() => run(confirmAction)}
                disabled={busy}
                className={`inline-flex h-11 flex-1 items-center justify-center gap-2 rounded-full text-sm font-bold text-white transition disabled:opacity-60 ${
                  confirmAction === "delete"
                    ? "bg-red-600 hover:bg-red-500"
                    : "bg-natalo-600 hover:bg-natalo-700"
                }`}
              >
                {busy && (
                  <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white" />
                )}
                {busy
                  ? "Memproses…"
                  : confirmAction === "delete"
                    ? "Hapus"
                    : "Arsipkan"}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
