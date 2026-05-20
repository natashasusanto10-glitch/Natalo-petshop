"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

/**
 * Tombol Akhiri Flash Sale untuk satu produk di list page.
 * Konfirmasi dialog → POST /api/admin/flash-sale/end → clear
 * Product.flashSaleEndsAt + discountPrice.
 */
export function EndFlashSaleButton({
  productId,
  productName,
}: {
  productId: string;
  productName: string;
}) {
  const router = useRouter();
  const [ending, setEnding] = useState(false);

  async function handleEnd() {
    const confirmed = confirm(
      `Akhiri Flash Sale untuk "${productName}"?\n\nProduk akan kembali ke harga normal. Aksi ini tidak bisa di-undo (tapi bisa create Flash Sale baru).`,
    );
    if (!confirmed) return;

    setEnding(true);
    try {
      const res = await fetch("/api/admin/flash-sale/end", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ productId }),
      });
      if (!res.ok) {
        const json = await res.json().catch(() => null);
        alert(json?.error ?? "Gagal mengakhiri Flash Sale.");
        return;
      }
      router.refresh();
    } catch {
      alert("Gagal mengakhiri Flash Sale. Periksa koneksi.");
    } finally {
      setEnding(false);
    }
  }

  return (
    <button
      type="button"
      onClick={handleEnd}
      disabled={ending}
      className="text-sm font-semibold text-red-600 hover:text-red-700 disabled:opacity-50"
    >
      {ending ? "Mengakhiri..." : "Akhiri"}
    </button>
  );
}
