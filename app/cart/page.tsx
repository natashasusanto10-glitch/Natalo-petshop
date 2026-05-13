"use client";

import Image from "next/image";
import Link from "next/link";
import dynamic from "next/dynamic";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { formatRupiah } from "@/lib/format";
import { EmptyCart } from "@/components/LoadingEmptyStates";
import { loadCart, saveCart, type CartItem } from "@/lib/cart";
import type { CartStockIssue } from "@/lib/cart-stock";
import { VoucherClaimBar } from "@/components/cart/VoucherClaimBar";
import { SwipeableCartRow } from "@/components/cart/SwipeableCartRow";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { hapticSuccess, hapticTap, hapticWarning } from "@/lib/native/haptics";
import { natToast } from "@/components/Toast";

// Voucher sheet & delete modal hanya muncul setelah user interaksi —
// lazy-load JS-nya supaya initial bundle cart page lebih ringan.
const CartVoucherSheet = dynamic(
  () => import("@/components/cart/CartVoucherSheet").then((m) => m.CartVoucherSheet),
  { ssr: false },
);

const ConfirmDeleteModal = dynamic(
  () => import("@/components/ConfirmDeleteModal").then((m) => m.ConfirmDeleteModal),
  { ssr: false },
);

const CHECKOUT_SELECTION_KEY = "checkout:selectedCartItems";
// Voucher pre-selection di cart, di-pickup oleh /checkout/page.tsx saat
// user klik Checkout (lihat applyCheckoutPricing di checkout page).
const CART_VOUCHER_KEY = "cart:voucher";

type CartAppliedMember = { code: string; discount: number; description: string };
type CartVoucherPreview = { discount: number; minimumOrder: number };

function cartKey(item: CartItem) {
  return `${item.productId}:${item.variantId ?? ""}`;
}

function itemSelectionLabel(kindCount: number, quantityCount: number) {
  if (kindCount <= 0) return "Belum ada produk dipilih";
  return `${kindCount} jenis produk (${quantityCount} item)`;
}

function TrashIcon({ className = "h-4 w-4" }: { className?: string }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
    >
      <polyline points="3 6 5 6 21 6" />
      <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
      <path d="M10 11v6M14 11v6" />
      <path d="M9 6V4h6v2" />
    </svg>
  );
}

export default function CartPage() {
  const router = useRouter();
  const [items, setItems] = useState<CartItem[]>([]);
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set());
  const [stockIssues, setStockIssues] = useState<CartStockIssue[]>([]);
  const [stockRefreshing, setStockRefreshing] = useState(false);
  const didInitialSelect = useRef(false);
  const didInitialStockRefresh = useRef(false);

  // Voucher state — di-persist ke sessionStorage supaya di-pickup oleh
  // /checkout/page.tsx saat user lanjut ke checkout.
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [voucherSheetOpen, setVoucherSheetOpen] = useState(false);
  const [memberVoucher, setMemberVoucher] = useState<CartAppliedMember | null>(null);
  const [memberVoucherPreview, setMemberVoucherPreview] = useState<CartVoucherPreview | null>(null);

  // Delete confirmation modal state
  const [isDeleteModalOpen, setIsDeleteModalOpen] = useState(false);
  const [deleteMode, setDeleteMode] = useState<"single" | "selected" | null>(null);
  const [targetItem, setTargetItem] = useState<CartItem | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  // Restore voucher pilihan dari sessionStorage saat mount
  useEffect(() => {
    try {
      const raw = sessionStorage.getItem(CART_VOUCHER_KEY);
      if (raw) {
        const parsed = JSON.parse(raw) as {
          member?: CartAppliedMember | null;
          private?: unknown;
        };
        if (parsed.member) setMemberVoucher(parsed.member);
        if (parsed.private) {
          sessionStorage.setItem(
            CART_VOUCHER_KEY,
            JSON.stringify({ member: parsed.member ?? null }),
          );
        }
      }
    } catch {
      // ignore corrupt session
    }
  }, []);

  // Cek login status
  useEffect(() => {
    fetch("/api/auth/me")
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (data?.name) setIsLoggedIn(true);
      })
      .catch(() => {});
  }, []);

  // Persist voucher selection setiap kali berubah
  useEffect(() => {
    try {
      if (memberVoucher) {
        sessionStorage.setItem(
          CART_VOUCHER_KEY,
          JSON.stringify({ member: memberVoucher }),
        );
      } else {
        sessionStorage.removeItem(CART_VOUCHER_KEY);
      }
    } catch {
      // ignore quota / disabled storage
    }
  }, [memberVoucher]);

  useEffect(() => {
    function syncCart() {
      const nextItems = loadCart();
      setItems(nextItems);
      setSelectedKeys((current) => {
        const available = new Set(nextItems.map(cartKey));
        if (!didInitialSelect.current) {
          didInitialSelect.current = true;
          return new Set(available);
        }
        return new Set([...current].filter((key) => available.has(key)));
      });
      if (!didInitialStockRefresh.current && nextItems.length > 0) {
        didInitialStockRefresh.current = true;
        void refreshCartStock(nextItems, { silent: true });
      }
    }
    function onStorage(e: StorageEvent) {
      if (e.key?.startsWith("cart")) syncCart();
    }

    syncCart();
    window.addEventListener("cart-updated", syncCart);
    window.addEventListener("storage", onStorage);
    return () => {
      window.removeEventListener("cart-updated", syncCart);
      window.removeEventListener("storage", onStorage);
    };
  }, []);

  const selectedItems = useMemo(
    () => items.filter((item) => selectedKeys.has(cartKey(item))),
    [items, selectedKeys]
  );
  const selectedCount = selectedItems.length;
  const selectedQuantity = selectedItems.reduce((sum, item) => sum + item.quantity, 0);
  const selectedSubtotal = selectedItems.reduce((sum, item) => sum + item.price * item.quantity, 0);
  // Total diskon dari kombinasi voucher member + private (capped at subtotal
  // supaya tidak negative — match logic backend).
  const voucherDiscount = Math.min(
    memberVoucher?.discount ?? 0,
    selectedSubtotal,
  );
  const selectedTotal = Math.max(selectedSubtotal - voucherDiscount, 0);
  const allSelected = items.length > 0 && selectedKeys.size === items.length;
  const selectionLabel = itemSelectionLabel(selectedCount, selectedQuantity);

  useEffect(() => {
    if (!isLoggedIn) {
      setMemberVoucherPreview(null);
      return;
    }

    let active = true;
    fetch(`/api/cart/vouchers?subtotal=${selectedSubtotal}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (!active) return;
        const vouchers = [
          ...((Array.isArray(data?.available) ? data.available : []) as CartVoucherPreview[]),
          ...((Array.isArray(data?.unavailable) ? data.unavailable : []) as CartVoucherPreview[]),
        ].filter((voucher) => voucher.discount > 0);
        vouchers.sort((a, b) => b.discount - a.discount);
        setMemberVoucherPreview(vouchers[0] ?? null);
      })
      .catch(() => {
        if (active) setMemberVoucherPreview(null);
      });

    return () => {
      active = false;
    };
  }, [isLoggedIn, selectedSubtotal]);

  function persist(next: CartItem[]) {
    setItems(next);
    saveCart(next);
  }

  async function refreshCartStock(
    itemsToValidate = items,
    opts: { silent?: boolean } = {},
  ) {
    if (itemsToValidate.length === 0) {
      setStockIssues([]);
      return { ok: true, items: itemsToValidate, issues: [] as CartStockIssue[] };
    }

    if (!opts.silent) setStockRefreshing(true);
    try {
      const response = await fetch("/api/cart/validate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items: itemsToValidate }),
      });
      const data = (await response.json()) as {
        ok?: boolean;
        changed?: boolean;
        items?: CartItem[];
        issues?: CartStockIssue[];
      };
      if (!response.ok || !Array.isArray(data.items)) {
        throw new Error("Gagal mengecek stok terbaru.");
      }

      const nextItems = data.items;
      const issues = Array.isArray(data.issues) ? data.issues : [];
      if (data.changed) {
        persist(nextItems);
        const available = new Set(nextItems.map(cartKey));
        setSelectedKeys((current) => new Set([...current].filter((key) => available.has(key))));
      }
      setStockIssues(issues);
      return { ok: issues.length === 0, items: nextItems, issues };
    } catch {
      const issues = [
        {
          key: "__stock-refresh__",
          productId: "",
          variantId: null,
          variantLabel: null,
          name: "Keranjang",
          requestedQuantity: 0,
          availableStock: 0,
          action: "removed" as const,
          message: "Stok terbaru belum bisa dicek. Coba refresh sebelum checkout.",
        },
      ];
      setStockIssues(issues);
      return { ok: false, items: itemsToValidate, issues };
    } finally {
      if (!opts.silent) setStockRefreshing(false);
    }
  }

  function toggleItem(key: string) {
    setSelectedKeys((current) => {
      const next = new Set(current);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  function toggleAll() {
    setSelectedKeys(allSelected ? new Set() : new Set(items.map(cartKey)));
  }

  function updateQty(key: string, quantity: number) {
    const existing = items.find((item) => cartKey(item) === key);
    const max = existing?.stock ?? Infinity;
    const clamped = Math.min(quantity, max);
    const noChange = existing && existing.quantity === clamped && quantity > 0;
    if (noChange) return;

    const next = items
      .map((item) => (cartKey(item) !== key ? item : { ...item, quantity: clamped }))
      .filter((item) => item.quantity > 0);

    if (quantity <= 0) {
      hapticWarning();
      setSelectedKeys((current) => {
        const nextSelected = new Set(current);
        nextSelected.delete(key);
        return nextSelected;
      });
    } else {
      hapticTap();
    }
    persist(next);
  }

  function removeSelected() {
    if (selectedKeys.size === 0) return;
    const next = items.filter((item) => !selectedKeys.has(cartKey(item)));
    setSelectedKeys(new Set());
    persist(next);
  }

  // Swipe-to-delete dengan undo toast — pattern iOS Mail / Tokopedia.
  // Optimistic remove langsung, lalu kasih 5 detik window untuk URUNGKAN.
  // Karena cart Natalo localStorage-based, tidak perlu defer commit ke server
  // (undo = re-insert ke posisi awal + saveCart ulang).
  function handleSwipeDelete(item: CartItem) {
    const targetKey = cartKey(item);
    const originalIndex = items.findIndex((i) => cartKey(i) === targetKey);
    if (originalIndex === -1) return;

    hapticTap();
    const nextItems = items.filter((i) => cartKey(i) !== targetKey);
    setSelectedKeys((current) => {
      const nextSelected = new Set(current);
      nextSelected.delete(targetKey);
      return nextSelected;
    });
    persist(nextItems);

    natToast(`"${item.name.slice(0, 30)}${item.name.length > 30 ? "…" : ""}" dihapus`, {
      kind: "default",
      action: {
        label: "URUNGKAN",
        onClick: () => {
          // Re-insert at original index berdasarkan SNAPSHOT saat swipe.
          // Pakai functional update supaya pakai latest items state (user
          // bisa edit lain selama 5s window).
          setItems((current) => {
            const restored = [...current];
            const insertAt = Math.min(originalIndex, restored.length);
            restored.splice(insertAt, 0, item);
            saveCart(restored);
            return restored;
          });
          setSelectedKeys((current) => {
            const nextSelected = new Set(current);
            nextSelected.add(targetKey);
            return nextSelected;
          });
          hapticSuccess();
        },
      },
    });
  }

  // ── Delete confirmation flow ─────────────────────────────────
  // Buka modal — TIDAK langsung hapus. User harus konfirmasi.

  function openDeleteSelectedModal() {
    if (selectedItems.length === 0) return;
    setDeleteMode("selected");
    setTargetItem(null);
    setIsDeleteModalOpen(true);
  }

  function openDeleteSingleModal(item: CartItem) {
    setDeleteMode("single");
    setTargetItem(item);
    setIsDeleteModalOpen(true);
  }

  function closeDeleteModal() {
    if (isDeleting) return;
    setIsDeleteModalOpen(false);
    setDeleteMode(null);
    setTargetItem(null);
  }

  async function handleConfirmDelete() {
    setIsDeleting(true);
    hapticSuccess();
    try {
      if (deleteMode === "single" && targetItem) {
        // Hapus item single — pakai cartKey + remove via filter (sama
        // pattern dgn updateQty(0) tapi tanpa side-effect quantity).
        const targetKey = cartKey(targetItem);
        const next = items.filter((item) => cartKey(item) !== targetKey);
        setSelectedKeys((current) => {
          const nextSelected = new Set(current);
          nextSelected.delete(targetKey);
          return nextSelected;
        });
        persist(next);
      } else if (deleteMode === "selected") {
        const next = items.filter((item) => !selectedKeys.has(cartKey(item)));
        setSelectedKeys(new Set());
        persist(next);
      }
      setIsDeleteModalOpen(false);
      setDeleteMode(null);
      setTargetItem(null);
    } finally {
      setIsDeleting(false);
    }
  }

  async function checkoutSelected() {
    if (selectedItems.length === 0) return;
    hapticTap();
    const result = await refreshCartStock(items);
    const selectedKeySet = new Set(selectedKeys);
    const nextSelectedItems = result.items.filter((item) => selectedKeySet.has(cartKey(item)));
    const selectedHasIssue = result.issues.some((issue) => selectedKeySet.has(issue.key));
    if (!result.ok || selectedHasIssue || nextSelectedItems.length === 0) {
      hapticWarning();
      return;
    }

    sessionStorage.setItem(CHECKOUT_SELECTION_KEY, JSON.stringify(nextSelectedItems));
    const ids = nextSelectedItems.map(cartKey).map(encodeURIComponent).join(",");
    router.push(`/checkout?cart_item_ids=${ids}`);
  }

  function handleBack() {
    if (typeof window !== "undefined" && window.history.length > 1) {
      router.back();
    } else {
      router.push("/products");
    }
  }

  return (
    <div className="mx-auto max-w-3xl px-4 pb-[calc(104px+env(safe-area-inset-bottom))] md:pb-10">
      <header className="sticky top-0 z-50 -mx-4 border-b border-gray-100 bg-white px-4 pb-3 [padding-top:calc(12px+env(safe-area-inset-top))]">
        <div className="mx-auto flex max-w-3xl items-center justify-between gap-3">
          <div className="flex min-w-0 items-center gap-3">
            <button
              type="button"
              onClick={handleBack}
              aria-label="Kembali"
              className="-ml-1 flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-gray-800 active:bg-gray-100"
            >
              <svg
                aria-hidden="true"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2.4}
                strokeLinecap="round"
                strokeLinejoin="round"
                className="h-6 w-6"
              >
                <path d="M15 18l-6-6 6-6" />
              </svg>
            </button>
            <h1 className="truncate text-2xl font-black tracking-tight text-gray-950 md:text-3xl">
              Keranjang
            </h1>
          </div>
          {items.length > 0 && (
            <button
              type="button"
              onClick={openDeleteSelectedModal}
              disabled={selectedCount === 0}
              className="inline-flex h-10 shrink-0 items-center gap-2 rounded-full px-3 text-sm font-bold text-red-500 transition active:bg-red-50 disabled:cursor-not-allowed disabled:text-gray-300 disabled:active:bg-transparent"
            >
              <TrashIcon />
              Hapus
            </button>
          )}
        </div>
        <p className="mx-auto mt-1 max-w-3xl pl-11 text-sm font-semibold text-gray-500">
          {selectionLabel}
        </p>
      </header>

      {items.length === 0 ? (
        <div className="mt-6 rounded-2xl border border-gray-100 bg-white md:mt-10">
          <EmptyCart />
        </div>
      ) : (
        <>
          <section className="mt-4 overflow-hidden rounded-2xl border border-blue-100 bg-white shadow-sm md:mt-8">
            <div className="flex items-center justify-between gap-3 border-b border-gray-100 px-4 py-3">
              <label className="flex min-w-0 items-center gap-3 text-sm font-black text-gray-900">
                <input
                  type="checkbox"
                  checked={allSelected}
                  onChange={toggleAll}
                  className="h-5 w-5 rounded border-gray-300 accent-blue-600"
                />
                Pilih Semua
              </label>
              <span className="shrink-0 text-xs font-semibold text-gray-500">
                {selectionLabel}
              </span>
            </div>

            <div className="px-4 py-3">
              <VoucherClaimBar
                isLoggedIn={isLoggedIn}
                memberVoucher={memberVoucher}
                previewVoucher={memberVoucherPreview}
                onClick={() => setVoucherSheetOpen(true)}
              />
            </div>

            {stockIssues.length > 0 && (
              <div className="border-y border-amber-100 bg-amber-50 px-4 py-3">
                <p className="text-xs font-black text-amber-800">Stok keranjang diperbarui</p>
                <div className="mt-1 space-y-1">
                  {stockIssues.slice(0, 3).map((issue) => (
                    <p key={issue.key} className="text-xs font-semibold text-amber-700">
                      {issue.message}
                    </p>
                  ))}
                </div>
              </div>
            )}

            <div className="divide-y divide-gray-100">
              {items.map((item) => {
                const key = cartKey(item);
                const checked = selectedKeys.has(key);
                const lineTotal = item.price * item.quantity;
                const showStockWarning =
                  item.stock != null && item.stock > 0 && item.quantity >= item.stock * 0.5;
                const remainingStock =
                  item.stock != null ? Math.max(item.stock - item.quantity, 0) : null;

                return (
                  <SwipeableCartRow key={key} onDelete={() => handleSwipeDelete(item)}>
                  <article className="bg-white px-4 py-4">
                    <div className="flex gap-3">
                      <input
                        type="checkbox"
                        checked={checked}
                        onChange={() => toggleItem(key)}
                        aria-label={`Pilih ${item.name}`}
                        className="mt-6 h-5 w-5 shrink-0 rounded border-gray-300 accent-blue-600"
                      />
                      <Link
                        href={`/products/${item.slug ?? item.productId}`}
                        aria-label={`Lihat detail produk ${item.name}`}
                        className="relative h-20 w-20 shrink-0 overflow-hidden rounded-xl bg-gray-100"
                      >
                        {item.imageUrl ? (
                          <Image
                            src={item.imageUrl}
                            alt={item.name}
                            fill
                            sizes="80px"
                            placeholder="blur"
                            blurDataURL={IMAGE_BLUR_GRAY}
                            className="object-cover"
                          />
                        ) : (
                          <div className="flex h-full w-full items-center justify-center text-2xl">🐾</div>
                        )}
                      </Link>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-start justify-between gap-2">
                          <div className="min-w-0">
                            <Link
                              href={`/products/${item.slug ?? item.productId}`}
                              className="line-clamp-2 text-sm font-bold leading-snug text-gray-900"
                            >
                              {item.name}
                            </Link>
                            {item.variantLabel && (
                              <p className="mt-1 inline-flex rounded-full bg-blue-50 px-2 py-0.5 text-[11px] font-bold text-blue-600">
                                {item.variantLabel}
                              </p>
                            )}
                          </div>
                          <button
                            type="button"
                            onClick={() => openDeleteSingleModal(item)}
                            aria-label={`Hapus ${item.name}`}
                            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-gray-300 transition hover:bg-red-50 hover:text-red-500"
                          >
                            <TrashIcon />
                          </button>
                        </div>

                        <div className="mt-2 flex items-end justify-between gap-3">
                          <div className="min-w-0">
                            <p className="text-base font-black text-gray-900">{formatRupiah(item.price)}</p>
                            <p className="mt-0.5 text-xs font-semibold text-gray-400">
                              Subtotal {formatRupiah(lineTotal)}
                            </p>
                            {item.stock != null && (
                              <p className="mt-0.5 text-[11px] font-semibold text-amber-600">
                                Stok {item.stock}
                              </p>
                            )}
                            {showStockWarning && remainingStock !== null && (
                              <p className="mt-1 inline-flex rounded-full bg-amber-50 px-2 py-1 text-[11px] font-black text-amber-700 ring-1 ring-amber-100">
                                Tersisa {remainingStock} dari {item.stock} stok
                              </p>
                            )}
                          </div>

                          <div className="flex shrink-0 items-center rounded-full border border-gray-200 bg-white">
                            <button
                              type="button"
                              onClick={() => updateQty(key, item.quantity - 1)}
                              className="flex h-9 w-9 items-center justify-center rounded-full text-lg font-bold text-gray-600 transition-all duration-75 hover:text-blue-600 active:scale-90"
                              aria-label="Kurangi"
                            >
                              {item.quantity <= 1 ? <TrashIcon className="h-3.5 w-3.5" /> : "−"}
                            </button>
                            <span className="w-8 text-center text-sm font-black text-gray-900">{item.quantity}</span>
                            <button
                              type="button"
                              onClick={() => updateQty(key, item.quantity + 1)}
                              disabled={item.stock != null && item.quantity >= item.stock}
                              className="flex h-9 w-9 items-center justify-center rounded-full text-lg font-bold text-gray-600 transition-all duration-75 hover:text-blue-600 active:scale-90 disabled:cursor-not-allowed disabled:opacity-40 disabled:active:scale-100"
                              aria-label="Tambah"
                            >
                              +
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  </article>
                  </SwipeableCartRow>
                );
              })}
            </div>
          </section>

          <section className="mt-4 hidden rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 md:block">
            <div className="space-y-1.5">
              <div className="flex items-center justify-between text-sm text-gray-600">
                <span>Subtotal produk</span>
                <span className="font-semibold text-gray-700">{formatRupiah(selectedSubtotal)}</span>
              </div>
              {voucherDiscount > 0 && (
                <div className="flex items-center justify-between text-sm text-amber-700">
                  <span className="inline-flex rounded-full bg-amber-50 px-2 py-1 text-xs font-black ring-1 ring-amber-100">
                    Hemat {formatRupiah(voucherDiscount)} dgn voucher
                  </span>
                  <span className="font-semibold">−{formatRupiah(voucherDiscount)}</span>
                </div>
              )}
              <div className="flex items-center justify-between border-t border-gray-100 pt-2.5">
                <span className="font-semibold text-gray-700">Total produk terpilih</span>
                <span className="text-xl font-black text-gray-900">{formatRupiah(selectedTotal)}</span>
              </div>
            </div>
            <p className="mt-2 text-xs text-gray-400">Ongkir dihitung saat checkout. Voucher dapat diubah sebelum bayar.</p>
            <button
              type="button"
              onClick={checkoutSelected}
              disabled={selectedCount === 0 || stockRefreshing}
              className="mt-5 flex w-full items-center justify-center rounded-full bg-blue-500 py-4 text-sm font-bold text-white transition-all duration-100 hover:bg-blue-600 active:scale-95 disabled:cursor-not-allowed disabled:bg-gray-300 disabled:active:scale-100"
            >
              {stockRefreshing ? "Cek stok..." : `Checkout (${selectedQuantity})`}
            </button>
            <Link
              href="/products"
              className="mt-3 flex w-full items-center justify-center rounded-full border border-gray-200 py-3 text-sm font-semibold text-gray-600 transition hover:border-blue-300 hover:text-blue-600"
            >
              Tambah produk lagi
            </Link>
          </section>
        </>
      )}

      <ConfirmDeleteModal
        open={isDeleteModalOpen}
        title={deleteMode === "single" ? "Hapus Produk Ini?" : "Hapus Produk?"}
        message={
          deleteMode === "single" && targetItem
            ? `Apakah kamu yakin ingin menghapus "${targetItem.name}" dari keranjang?`
            : `Apakah kamu yakin ingin menghapus ${selectedItems.length} jenis produk dari keranjang?`
        }
        loading={isDeleting}
        onCancel={closeDeleteModal}
        onConfirm={handleConfirmDelete}
      />

      <CartVoucherSheet
        open={voucherSheetOpen}
        onClose={() => setVoucherSheetOpen(false)}
        isLoggedIn={isLoggedIn}
        subtotal={selectedSubtotal}
        selectedMemberCode={memberVoucher?.code ?? null}
        onSelectMember={(code, discount, description) => {
          if (!code) {
            setMemberVoucher(null);
          } else {
            setMemberVoucher({ code, discount, description });
          }
        }}
        onRequireLogin={() => {
          setVoucherSheetOpen(false);
          router.push("/login?next=/cart");
        }}
      />

      {items.length > 0 && (
        <div className="fixed inset-x-0 bottom-0 z-40 border-t border-gray-100 bg-white px-4 py-3 shadow-[0_-4px_12px_rgba(0,0,0,0.06)] md:hidden [padding-bottom:calc(12px+env(safe-area-inset-bottom))]">
          <div className="mx-auto flex max-w-3xl items-center gap-3">
            <label className="flex shrink-0 items-center gap-2 text-xs font-bold text-gray-600">
              <input
                type="checkbox"
                checked={allSelected}
                onChange={toggleAll}
                className="h-5 w-5 rounded border-gray-300 accent-blue-600"
              />
              Semua
            </label>
            <div className="min-w-0 flex-1 text-right">
              <p className="text-[11px] font-semibold text-gray-500">
                {voucherDiscount > 0 ? `Hemat ${formatRupiah(voucherDiscount)} dgn voucher` : "Total"}
              </p>
              <p className="truncate text-base font-black text-gray-900">{formatRupiah(selectedTotal)}</p>
            </div>
            <button
              type="button"
              onClick={checkoutSelected}
              disabled={selectedCount === 0 || stockRefreshing}
              className="flex h-12 shrink-0 items-center justify-center rounded-full bg-blue-500 px-5 text-sm font-black text-white transition-transform duration-100 active:scale-95 active:opacity-90 disabled:cursor-not-allowed disabled:bg-gray-300 disabled:active:scale-100"
            >
              {stockRefreshing ? "Cek stok..." : `Checkout (${selectedQuantity})`}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
