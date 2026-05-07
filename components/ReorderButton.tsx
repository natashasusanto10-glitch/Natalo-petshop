"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { ReorderCartItem, ReorderItemResult, ReorderResult } from "@/lib/reorder";
import { formatRupiah } from "@/lib/format";

// ── Cart helpers (sync dengan lib lain) ────────────────────────
type CartItem = {
  productId: string;
  variantId?: string | null;
  variantLabel?: string | null;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
  stock?: number;
  imageUrl?: string | null;
};

function loadCart(): CartItem[] {
  if (typeof window === "undefined") return [];
  try {
    return JSON.parse(localStorage.getItem("cart") ?? "[]");
  } catch {
    return [];
  }
}

function saveCart(items: CartItem[]) {
  localStorage.setItem("cart", JSON.stringify(items));
  window.dispatchEvent(new Event("cart-updated"));
}

function cartKey(productId: string, variantId: string | null | undefined) {
  return `${productId}:${variantId ?? ""}`;
}

/**
 * Merge added + adjusted items ke localStorage cart.
 * Dedup by (productId, variantId): jumlahkan qty, clamp ke stok.
 * Return jumlah item yang berhasil ditambahkan.
 */
function mergeToCart(items: ReorderCartItem[]): number {
  const cart = loadCart();
  let count = 0;

  for (const item of items) {
    const key = cartKey(item.productId, item.variantId);
    const existing = cart.find((c) => cartKey(c.productId, c.variantId) === key);

    if (existing) {
      const merged = Math.min(item.stock, existing.quantity + item.quantity);
      existing.quantity = merged;
      existing.stock = item.stock;
      existing.price = item.price; // refresh harga ke yang current
      existing.imageUrl = item.imageUrl;
    } else {
      cart.push({
        productId: item.productId,
        variantId: item.variantId,
        variantLabel: item.variantLabel,
        name: item.name,
        price: item.price,
        quantity: item.quantity,
        weightGram: item.weightGram,
        stock: item.stock,
        imageUrl: item.imageUrl,
      });
    }
    count++;
  }

  saveCart(cart);
  return count;
}

// ── Main component ─────────────────────────────────────────────
interface Props {
  orderNumber: string;
  /** Kalau diset, hanya reorder item ini */
  itemId?: string;
  /** Mode tampilan: full button atau small */
  variant?: "primary" | "outline" | "ghost";
  /** Custom label tombol */
  children?: React.ReactNode;
  className?: string;
}

export function ReorderButton({
  orderNumber,
  itemId,
  variant = "outline",
  children,
  className,
}: Props) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<ReorderResult | null>(null);

  async function handleClick() {
    if (loading) return;
    setLoading(true);
    try {
      const res = await fetch(`/api/orders/${orderNumber}/reorder`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(itemId ? { itemId } : {}),
      });
      const data: ReorderResult | { error: string } = await res.json();

      if (!res.ok) {
        alert("error" in data ? data.error : "Gagal memproses reorder.");
        return;
      }
      const reorderData = data as ReorderResult;

      // Merge added + adjusted ke cart
      const itemsToAdd = [
        ...reorderData.added.map((r) => (r as { item: ReorderCartItem }).item),
        ...reorderData.adjusted.map((r) => (r as { item: ReorderCartItem }).item),
      ];

      if (itemsToAdd.length > 0) mergeToCart(itemsToAdd);

      // Kalau ada skipped/adjusted → tampilkan modal
      if (reorderData.skipped.length > 0 || reorderData.adjusted.length > 0) {
        setResult(reorderData);
      } else if (reorderData.added.length > 0) {
        // Semua sukses → langsung redirect
        router.push("/cart");
      } else {
        alert("Tidak ada item yang bisa di-reorder.");
      }
    } catch (e) {
      alert(e instanceof Error ? e.message : "Gagal memproses reorder.");
    } finally {
      setLoading(false);
    }
  }

  const baseStyle =
    "rounded-full text-sm font-bold transition disabled:cursor-not-allowed disabled:opacity-50";
  const styles = {
    primary: "bg-natalo-600 px-5 py-2.5 text-white hover:bg-natalo-700",
    outline:
      "border border-natalo-300 bg-white px-4 py-2 text-natalo-700 hover:bg-natalo-50",
    ghost: "px-3 py-1.5 text-natalo-600 hover:bg-natalo-50",
  };

  return (
    <>
      <button
        type="button"
        onClick={handleClick}
        disabled={loading}
        className={`${baseStyle} ${styles[variant]} ${className ?? ""}`}
      >
        {loading ? "Memproses..." : children ?? "🔄 Beli Lagi"}
      </button>

      {result && (
        <ReorderResultModal
          result={result}
          onClose={() => setResult(null)}
          onContinue={() => {
            setResult(null);
            router.push("/cart");
          }}
        />
      )}
    </>
  );
}

// ── Modal hasil reorder ────────────────────────────────────────
function ReorderResultModal({
  result,
  onClose,
  onContinue,
}: {
  result: ReorderResult;
  onClose: () => void;
  onContinue: () => void;
}) {
  const totalAdded = result.added.length + result.adjusted.length;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div className="max-h-[90vh] w-full max-w-lg overflow-hidden rounded-2xl bg-white shadow-xl">
        <div className="border-b border-gray-100 p-5">
          <h2 className="text-lg font-black text-gray-900">Hasil Pesan Lagi</h2>
          <p className="mt-0.5 text-sm text-gray-500">
            {totalAdded > 0
              ? `${totalAdded} produk berhasil ditambahkan ke keranjang.`
              : "Tidak ada produk yang bisa ditambahkan."}
          </p>
        </div>

        <div className="max-h-[60vh] overflow-y-auto p-5">
          <ul className="space-y-3 text-sm">
            {/* Added */}
            {result.added.map((r, i) => {
              const a = r as Extract<ReorderItemResult, { status: "added" }>;
              return (
                <li key={`a-${i}`} className="flex gap-3">
                  <span className="text-green-500">✓</span>
                  <div className="flex-1">
                    <p className="font-semibold text-gray-900">{a.item.name}</p>
                    <p className="text-xs text-gray-500">
                      Masuk keranjang • {a.item.quantity} pcs •{" "}
                      {formatRupiah(a.item.price)}
                    </p>
                    {a.priceChanged && (
                      <p className="mt-0.5 text-xs text-amber-600">
                        Harga {a.item.price > a.previousPrice ? "naik" : "turun"} dari{" "}
                        {formatRupiah(a.previousPrice)} → {formatRupiah(a.item.price)}
                      </p>
                    )}
                  </div>
                </li>
              );
            })}

            {/* Adjusted */}
            {result.adjusted.map((r, i) => {
              const a = r as Extract<ReorderItemResult, { status: "adjusted" }>;
              return (
                <li key={`adj-${i}`} className="flex gap-3">
                  <span className="text-amber-500">⚠</span>
                  <div className="flex-1">
                    <p className="font-semibold text-gray-900">{a.item.name}</p>
                    <p className="text-xs text-amber-600">
                      Stok cuma tersisa {a.availableStock} (kamu pesan{" "}
                      {a.requestedQuantity}). Disesuaikan ke {a.item.quantity}.
                    </p>
                    {a.priceChanged && (
                      <p className="mt-0.5 text-xs text-amber-600">
                        Harga sekarang {formatRupiah(a.item.price)} (sebelumnya{" "}
                        {formatRupiah(a.previousPrice)})
                      </p>
                    )}
                  </div>
                </li>
              );
            })}

            {/* Skipped */}
            {result.skipped.map((r, i) => {
              const s = r as Extract<ReorderItemResult, { status: "skipped" }>;
              return (
                <li key={`s-${i}`} className="flex gap-3">
                  <span className="text-red-400">✗</span>
                  <div className="flex-1">
                    <p className="font-semibold text-gray-900">{s.name}</p>
                    <p className="text-xs text-red-500">{s.reason}</p>
                  </div>
                </li>
              );
            })}
          </ul>
        </div>

        <div className="flex gap-3 border-t border-gray-100 p-5">
          {totalAdded > 0 ? (
            <>
              <button
                onClick={onContinue}
                className="flex-1 rounded-full bg-natalo-600 py-3 text-sm font-bold text-white hover:bg-natalo-700"
              >
                Lanjut ke Keranjang →
              </button>
              <button
                onClick={onClose}
                className="rounded-full border border-gray-200 px-5 py-3 text-sm font-bold text-gray-600 hover:bg-gray-50"
              >
                Tutup
              </button>
            </>
          ) : (
            <button
              onClick={onClose}
              className="flex-1 rounded-full bg-gray-100 py-3 text-sm font-bold text-gray-700 hover:bg-gray-200"
            >
              Tutup
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
