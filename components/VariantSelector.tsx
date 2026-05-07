"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { formatRupiah } from "@/lib/format";
import type { StoreVariantAttribute, StoreProductVariant } from "@/lib/products";
import { loadCart, saveCart } from "@/lib/cart";

function cartKey(productId: string, variantId: string | null | undefined) {
  return `${productId}:${variantId ?? ""}`;
}

// ── Props ──────────────────────────────────────────────────────
interface Props {
  product: { id: string; name: string; imageUrl: string | null };
  attrs: StoreVariantAttribute[];
  variants: StoreProductVariant[];
  /** callback agar foto utama halaman bisa ganti saat varian dipilih */
  onVariantImage?: (url: string | null) => void;
}

export function VariantSelector({ product, attrs, variants, onVariantImage }: Props) {
  // ── State ──────────────────────────────────────────────────────
  // selected[attributeId] = optionId
  const [selected, setSelected] = useState<Record<string, string>>({});
  const [qty, setQty] = useState(1);
  const [toast, setToast] = useState(false);

  // ── Derived ───────────────────────────────────────────────────
  const sortedAttrs = useMemo(
    () => [...attrs].sort((a, b) => a.position - b.position),
    [attrs]
  );

  const allSelected = sortedAttrs.every((a) => !!selected[a.id]);

  // Temukan variant yang cocok dengan semua pilihan
  const currentVariant = useMemo<StoreProductVariant | null>(() => {
    if (!allSelected) return null;
    return (
      variants.find(
        (v) =>
          v.isActive &&
          !v.deletedAt &&
          sortedAttrs.every((a) =>
            v.options.some((o) => o.optionId === selected[a.id])
          )
      ) ?? null
    );
  }, [allSelected, selected, sortedAttrs, variants]);

  // Harga tampil: range sebelum pilih, single setelah pilih
  const priceDisplay = useMemo(() => {
    if (currentVariant) return formatRupiah(currentVariant.price);
    const activePrices = variants
      .filter((v) => v.isActive && !v.deletedAt)
      .map((v) => v.price);
    if (!activePrices.length) return formatRupiah(0);
    const min = Math.min(...activePrices);
    const max = Math.max(...activePrices);
    return min === max
      ? formatRupiah(min)
      : `${formatRupiah(min)} – ${formatRupiah(max)}`;
  }, [currentVariant, variants]);

  // Total stok
  const stockDisplay = useMemo(() => {
    if (currentVariant) return currentVariant.stock;
    return variants
      .filter((v) => v.isActive && !v.deletedAt)
      .reduce((s, v) => s + v.stock, 0);
  }, [currentVariant, variants]);

  const maxQty = currentVariant ? currentVariant.stock : 0;
  const outOfStock = currentVariant ? currentVariant.stock === 0 : false;

  // Broadcast state ke StickyAddToCartBar
  const minPrice = useMemo(() => {
    const active = variants.filter((v) => v.isActive && !v.deletedAt).map((v) => v.price);
    return active.length ? Math.min(...active) : 0;
  }, [variants]);

  useEffect(() => {
    window.dispatchEvent(
      new CustomEvent("pdp-state", {
        detail: {
          hasVariants: true,
          canAdd: !!currentVariant && !outOfStock,
          outOfStock: !!currentVariant && outOfStock,
          price: currentVariant?.price ?? minPrice,
        },
      }),
    );
  }, [currentVariant, outOfStock, minPrice]);

  // ── Disabled check untuk tombol opsi ─────────────────────────
  const isOptionDisabled = useCallback(
    (attrIdx: number, optionId: string): boolean => {
      return !variants.some((v) => {
        if (!v.isActive || v.deletedAt || v.stock <= 0) return false;
        if (!v.options.some((o) => o.optionId === optionId)) return false;
        // Cek pilihan atribut sebelumnya
        for (let i = 0; i < attrIdx; i++) {
          const sel = selected[sortedAttrs[i].id];
          if (sel && !v.options.some((o) => o.optionId === sel)) return false;
        }
        return true;
      });
    },
    [variants, selected, sortedAttrs]
  );

  // ── Pilih opsi ────────────────────────────────────────────────
  function selectOption(attrId: string, optionId: string, attrIdx: number) {
    setSelected((prev) => {
      const next = { ...prev, [attrId]: optionId };
      // Reset pilihan atribut SETELAH yang ini kalau tidak kompatibel
      for (let i = attrIdx + 1; i < sortedAttrs.length; i++) {
        const nextAttr = sortedAttrs[i];
        const nextSel = next[nextAttr.id];
        if (nextSel) {
          // Cek apakah pilihan sebelumnya masih kompatibel
          const stillValid = variants.some(
            (v) =>
              v.isActive &&
              !v.deletedAt &&
              v.stock > 0 &&
              sortedAttrs.slice(0, i + 1).every((a) =>
                v.options.some((o) => o.optionId === next[a.id])
              )
          );
          if (!stillValid) delete next[nextAttr.id];
        }
      }
      return next;
    });
    setQty(1);
  }

  // Listen trigger dari StickyAddToCartBar
  useEffect(() => {
    function onTrigger() {
      addToCart(false);
    }
    window.addEventListener("pdp-add-to-cart", onTrigger);
    return () => window.removeEventListener("pdp-add-to-cart", onTrigger);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentVariant, allSelected, qty, outOfStock]);

  // ── Add to cart ───────────────────────────────────────────────
  function addToCart(redirectToCheckout = false) {
    if (!currentVariant || !allSelected || outOfStock) return;

    const label = sortedAttrs
      .map((a) => {
        const optId = selected[a.id];
        return a.options.find((o) => o.id === optId)?.value ?? "";
      })
      .filter(Boolean)
      .join(" / ");

    // Ganti gambar utama kalau variant punya foto sendiri
    if (onVariantImage) onVariantImage(currentVariant.imageUrl);

    const cart = loadCart();
    const key = cartKey(product.id, currentVariant.id);
    const existing = cart.find(
      (i) => cartKey(i.productId, i.variantId) === key
    );

    if (existing) {
      existing.quantity = Math.min(maxQty, existing.quantity + qty);
      existing.stock = currentVariant.stock;
    } else {
      cart.push({
        productId: product.id,
        variantId: currentVariant.id,
        variantLabel: label,
        name: product.name,
        price: currentVariant.price,
        quantity: qty,
        weightGram: currentVariant.weightGram,
        stock: currentVariant.stock,
        imageUrl: currentVariant.imageUrl ?? product.imageUrl,
      });
    }

    saveCart(cart);

    if (redirectToCheckout) {
      window.location.href = "/checkout";
    } else {
      setQty(1);
      setToast(true);
      setTimeout(() => setToast(false), 2500);
    }
  }

  // ── Render ────────────────────────────────────────────────────
  return (
    <div className="space-y-5">
      {/* Harga */}
      <div className="rounded-2xl bg-gray-50 p-5">
        <p className="text-3xl font-black text-natalo-600">{priceDisplay}</p>
        <p className="mt-1 text-sm text-gray-400">
          Stok:{" "}
          {currentVariant
            ? outOfStock
              ? "Habis"
              : `${currentVariant.stock} tersedia`
            : `${stockDisplay} total semua varian`}
        </p>
      </div>

      {/* Pilihan atribut */}
      <div className="space-y-4">
        {sortedAttrs.map((attr, attrIdx) => (
          <div key={attr.id}>
            <p className="mb-2 text-sm font-semibold text-gray-700">
              {attr.name}
              {selected[attr.id] && (
                <span className="ml-2 font-normal text-natalo-600">
                  {attr.options.find((o) => o.id === selected[attr.id])?.value}
                </span>
              )}
            </p>
            <div className="flex flex-wrap gap-2">
              {[...attr.options]
                .sort((a, b) => a.position - b.position)
                .map((opt) => {
                  const isSelected = selected[attr.id] === opt.id;
                  const disabled = isOptionDisabled(attrIdx, opt.id);
                  return (
                    <button
                      key={opt.id}
                      type="button"
                      disabled={disabled}
                      onClick={() => selectOption(attr.id, opt.id, attrIdx)}
                      className={`rounded-xl border px-4 py-2 text-sm font-semibold transition ${
                        isSelected
                          ? "border-natalo-600 bg-natalo-50 text-natalo-700"
                          : disabled
                          ? "cursor-not-allowed border-gray-200 bg-gray-50 text-gray-300 line-through"
                          : "border-gray-200 text-gray-700 hover:border-natalo-400 hover:text-natalo-600"
                      }`}
                    >
                      {opt.value}
                    </button>
                  );
                })}
            </div>
          </div>
        ))}
      </div>

      {/* Qty stepper */}
      {currentVariant && (
        <div>
          <p className="mb-2 text-sm font-medium text-gray-700">Jumlah</p>
          <div className="flex items-center gap-3">
            <button
              onClick={() => setQty((q) => Math.max(1, q - 1))}
              disabled={qty <= 1}
              className="flex h-10 w-10 items-center justify-center rounded-full border border-gray-200 text-lg font-bold text-gray-700 transition hover:border-natalo-400 hover:text-natalo-600 disabled:opacity-40"
            >
              −
            </button>
            <span className="w-8 text-center text-lg font-bold text-gray-900">{qty}</span>
            <button
              onClick={() => setQty((q) => Math.min(maxQty, q + 1))}
              disabled={outOfStock || qty >= maxQty}
              className="flex h-10 w-10 items-center justify-center rounded-full border border-gray-200 text-lg font-bold text-gray-700 transition hover:border-natalo-400 hover:text-natalo-600 disabled:opacity-40"
            >
              +
            </button>
            {maxQty > 0 && qty >= maxQty && (
              <span className="text-xs text-red-400">Stok tersisa: {maxQty}</span>
            )}
          </div>
        </div>
      )}

      {/* Tombol aksi */}
      <div className="space-y-3">
        {!allSelected && (
          <p className="text-sm text-gray-400">
            ← Pilih{" "}
            {sortedAttrs
              .filter((a) => !selected[a.id])
              .map((a) => a.name)
              .join(", ")}{" "}
            terlebih dahulu
          </p>
        )}

        <button
          onClick={() => addToCart(false)}
          disabled={!allSelected || outOfStock}
          className={`w-full rounded-full py-4 text-sm font-bold text-white transition ${
            toast
              ? "bg-green-500"
              : !allSelected || outOfStock
              ? "cursor-not-allowed bg-gray-300"
              : "bg-natalo-600 hover:bg-natalo-700"
          }`}
        >
          {toast
            ? "✓ Ditambahkan ke Keranjang"
            : outOfStock
            ? "Stok Habis"
            : allSelected
            ? "+ Keranjang"
            : "Pilih Varian"}
        </button>

        <button
          onClick={() => addToCart(true)}
          disabled={!allSelected || outOfStock}
          className="w-full rounded-full border-2 border-natalo-600 py-4 text-sm font-bold text-natalo-600 transition hover:bg-natalo-50 disabled:cursor-not-allowed disabled:border-gray-200 disabled:text-gray-300"
        >
          Beli Sekarang
        </button>
      </div>
    </div>
  );
}
