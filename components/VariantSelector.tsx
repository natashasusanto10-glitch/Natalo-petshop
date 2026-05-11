"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { formatRupiah } from "@/lib/format";
import type { StoreVariantAttribute, StoreProductVariant } from "@/lib/products";
import { addItemToCart } from "@/lib/cart-actions";
import { AddToCartBottomSheet } from "@/components/AddToCartBottomSheet";

// Props
interface Props {
  product: { id: string; slug?: string; name: string; imageUrl: string | null };
  attrs: StoreVariantAttribute[];
  variants: StoreProductVariant[];
  /** callback agar foto utama halaman bisa ganti saat varian dipilih */
  onVariantImage?: (url: string | null) => void;
}

export function VariantSelector({ product, attrs, variants, onVariantImage }: Props) {
  // State
  // selected[attributeId] = optionId
  const [selected, setSelected] = useState<Record<string, string>>({});
  const [sheetOpen, setSheetOpen] = useState(false);

  // Derived
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
      : `${formatRupiah(min)} - ${formatRupiah(max)}`;
  }, [currentVariant, variants]);

  // Total stok
  const stockDisplay = useMemo(() => {
    if (currentVariant) return currentVariant.stock;
    return variants
      .filter((v) => v.isActive && !v.deletedAt)
      .reduce((s, v) => s + v.stock, 0);
  }, [currentVariant, variants]);

  const outOfStock = currentVariant ? currentVariant.stock === 0 : false;

  const selectedLabel = useMemo(
    () =>
      sortedAttrs
        .map((a) => {
          const optId = selected[a.id];
          return a.options.find((o) => o.id === optId)?.value ?? "";
        })
        .filter(Boolean)
        .join(" / "),
    [selected, sortedAttrs],
  );

  const sheetItem = useMemo(() => {
    if (!currentVariant || !allSelected || outOfStock) return null;

    return {
      productId: product.id,
      slug: product.slug,
      variantId: currentVariant.id,
      variantLabel: selectedLabel,
      name: product.name,
      price: currentVariant.price,
      weightGram: currentVariant.weightGram,
      stock: currentVariant.stock,
      imageUrl: currentVariant.imageUrl ?? product.imageUrl,
    };
  }, [allSelected, currentVariant, outOfStock, product.id, product.imageUrl, product.name, product.slug, selectedLabel]);

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

  // Disabled check untuk tombol opsi
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

  // Pilih opsi
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
  }

  // Listen trigger dari StickyAddToCartBar
  useEffect(() => {
    function onAddToCart() {
      if (!currentVariant || !allSelected || outOfStock) return;
      if (onVariantImage) onVariantImage(currentVariant.imageUrl);
      setSheetOpen(true);
    }
    function onBuyNow() {
      addToCart(true);
    }
    window.addEventListener("pdp-add-to-cart", onAddToCart);
    window.addEventListener("pdp-buy-now", onBuyNow);
    return () => {
      window.removeEventListener("pdp-add-to-cart", onAddToCart);
      window.removeEventListener("pdp-buy-now", onBuyNow);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentVariant, allSelected, outOfStock]);

  // Add to cart
  function addToCart(redirectToCheckout = false) {
    if (!currentVariant || !allSelected || outOfStock) return;

    // Ganti gambar utama kalau variant punya foto sendiri
    if (onVariantImage) onVariantImage(currentVariant.imageUrl);

    const result = addItemToCart(
      {
        productId: product.id,
        slug: product.slug,
        variantId: currentVariant.id,
        variantLabel: selectedLabel,
        name: product.name,
        price: currentVariant.price,
        quantity: 1,
        subtotal: currentVariant.price,
        weightGram: currentVariant.weightGram,
        stock: currentVariant.stock,
        imageUrl: currentVariant.imageUrl ?? product.imageUrl,
      },
      { showToast: !redirectToCheckout },
    );

    if (!result.ok) return;

    if (redirectToCheckout) {
      window.location.href = "/checkout";
    }
  }

  // Render
  return (
    <>
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

        <div className="space-y-3">
          {!allSelected && (
            <p className="text-sm text-gray-400">
              Pilih{" "}
              {sortedAttrs
                .filter((a) => !selected[a.id])
                .map((a) => a.name)
                .join(", ")}{" "}
              terlebih dahulu
            </p>
          )}
        </div>
      </div>
      <AddToCartBottomSheet
        open={sheetOpen}
        item={sheetItem}
        onClose={() => setSheetOpen(false)}
      />
    </>
  );
}
