"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { formatRupiah } from "@/lib/format";
import { EmptyCart } from "@/components/LoadingEmptyStates";
import { loadCart, saveCart, type CartItem } from "@/lib/cart";

const CHECKOUT_SELECTION_KEY = "checkout:selectedCartItems";

function cartKey(item: CartItem) {
  return `${item.productId}:${item.variantId ?? ""}`;
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
  const didInitialSelect = useRef(false);

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
    }
    function onStorage(e: StorageEvent) {
      if (e.key === "cart") syncCart();
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
  const selectedTotal = selectedItems.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const allSelected = items.length > 0 && selectedKeys.size === items.length;

  function persist(next: CartItem[]) {
    setItems(next);
    saveCart(next);
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
    const next = items
      .map((item) => {
        if (cartKey(item) !== key) return item;
        const max = item.stock ?? Infinity;
        return { ...item, quantity: Math.min(quantity, max) };
      })
      .filter((item) => item.quantity > 0);

    if (quantity <= 0) {
      setSelectedKeys((current) => {
        const nextSelected = new Set(current);
        nextSelected.delete(key);
        return nextSelected;
      });
    }
    persist(next);
  }

  function removeSelected() {
    if (selectedKeys.size === 0) return;
    const next = items.filter((item) => !selectedKeys.has(cartKey(item)));
    setSelectedKeys(new Set());
    persist(next);
  }

  function checkoutSelected() {
    if (selectedItems.length === 0) return;
    sessionStorage.setItem(CHECKOUT_SELECTION_KEY, JSON.stringify(selectedItems));
    const ids = selectedItems.map(cartKey).map(encodeURIComponent).join(",");
    router.push(`/checkout?cart_item_ids=${ids}`);
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-4 pb-[calc(150px+env(safe-area-inset-bottom))] md:py-10 md:pb-10">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-black tracking-tight text-gray-900 md:text-3xl">Keranjang</h1>
          <p className="mt-1 text-sm font-semibold text-gray-500">
            {selectedCount > 0 ? `${selectedCount} produk terpilih` : "Belum ada produk dipilih"}
          </p>
        </div>
        {items.length > 0 && (
          <button
            type="button"
            onClick={removeSelected}
            disabled={selectedCount === 0}
            className="inline-flex h-10 items-center gap-2 rounded-full px-3 text-sm font-bold text-red-500 transition hover:bg-red-50 disabled:cursor-not-allowed disabled:text-gray-300 disabled:hover:bg-transparent"
          >
            <TrashIcon />
            Hapus
          </button>
        )}
      </div>

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
                {selectedQuantity} item
              </span>
            </div>

            <div className="bg-blue-50/70 px-4 py-3">
              <div className="flex items-start gap-2 text-xs text-blue-700">
                <span className="mt-0.5 inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-white font-black text-blue-600">
                  %
                </span>
                <div>
                  <p className="font-black">Voucher tersedia</p>
                  <p className="mt-0.5 text-blue-600">Gratis ongkir dan diskon khusus bisa dipakai saat checkout.</p>
                </div>
              </div>
            </div>

            <div className="divide-y divide-gray-100">
              {items.map((item) => {
                const key = cartKey(item);
                const checked = selectedKeys.has(key);
                const lineTotal = item.price * item.quantity;

                return (
                  <article key={key} className="bg-white px-4 py-4">
                    <div className="flex gap-3">
                      <input
                        type="checkbox"
                        checked={checked}
                        onChange={() => toggleItem(key)}
                        aria-label={`Pilih ${item.name}`}
                        className="mt-6 h-5 w-5 shrink-0 rounded border-gray-300 accent-blue-600"
                      />
                      <div className="relative h-20 w-20 shrink-0 overflow-hidden rounded-xl bg-gray-100">
                        {item.imageUrl ? (
                          <Image
                            src={item.imageUrl}
                            alt={item.name}
                            fill
                            sizes="80px"
                            className="object-cover"
                          />
                        ) : (
                          <div className="flex h-full w-full items-center justify-center text-2xl">🐾</div>
                        )}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-start justify-between gap-2">
                          <div className="min-w-0">
                            <p className="line-clamp-2 text-sm font-bold leading-snug text-gray-900">
                              {item.name}
                            </p>
                            {item.variantLabel && (
                              <p className="mt-1 inline-flex rounded-full bg-blue-50 px-2 py-0.5 text-[11px] font-bold text-blue-600">
                                {item.variantLabel}
                              </p>
                            )}
                          </div>
                          <button
                            type="button"
                            onClick={() => updateQty(key, 0)}
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
                          </div>

                          <div className="flex shrink-0 items-center rounded-full border border-gray-200 bg-white">
                            <button
                              type="button"
                              onClick={() => updateQty(key, item.quantity - 1)}
                              className="flex h-9 w-9 items-center justify-center rounded-full text-lg font-bold text-gray-600 transition hover:text-blue-600"
                              aria-label="Kurangi"
                            >
                              {item.quantity <= 1 ? <TrashIcon className="h-3.5 w-3.5" /> : "−"}
                            </button>
                            <span className="w-8 text-center text-sm font-black text-gray-900">{item.quantity}</span>
                            <button
                              type="button"
                              onClick={() => updateQty(key, item.quantity + 1)}
                              disabled={item.stock != null && item.quantity >= item.stock}
                              className="flex h-9 w-9 items-center justify-center rounded-full text-lg font-bold text-gray-600 transition hover:text-blue-600 disabled:cursor-not-allowed disabled:opacity-40"
                              aria-label="Tambah"
                            >
                              +
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  </article>
                );
              })}
            </div>
          </section>

          <section className="mt-4 hidden rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 md:block">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-gray-700">Total produk terpilih</span>
              <span className="text-xl font-black text-gray-900">{formatRupiah(selectedTotal)}</span>
            </div>
            <p className="mt-2 text-xs text-gray-400">Ongkir dan voucher dihitung saat checkout.</p>
            <button
              type="button"
              onClick={checkoutSelected}
              disabled={selectedCount === 0}
              className="mt-5 flex w-full items-center justify-center rounded-full bg-blue-500 py-4 text-sm font-bold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:bg-gray-300"
            >
              Checkout ({selectedCount})
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

      {items.length > 0 && (
        <div className="fixed inset-x-0 z-40 border-t border-gray-100 bg-white px-4 py-3 shadow-[0_-4px_12px_rgba(0,0,0,0.06)] md:hidden [bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom))]">
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
              <p className="text-[11px] font-semibold text-gray-500">Total</p>
              <p className="truncate text-base font-black text-gray-900">{formatRupiah(selectedTotal)}</p>
            </div>
            <button
              type="button"
              onClick={checkoutSelected}
              disabled={selectedCount === 0}
              className="flex h-12 shrink-0 items-center justify-center rounded-full bg-blue-500 px-5 text-sm font-black text-white active:opacity-90 disabled:cursor-not-allowed disabled:bg-gray-300"
            >
              Checkout ({selectedCount})
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
