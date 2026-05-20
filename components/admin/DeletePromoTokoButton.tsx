"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

/**
 * Tombol Hapus untuk Promo Toko di list page. Konfirmasi dialog dulu
 * sebelum DELETE /api/admin/discounts/promo-toko/[id]. Setelah hapus,
 * router.refresh() supaya list update.
 */
export function DeletePromoTokoButton({
  promoId,
  promoName,
}: {
  promoId: string;
  promoName: string;
}) {
  const router = useRouter();
  const [deleting, setDeleting] = useState(false);

  async function handleDelete() {
    const confirmed = confirm(
      `Hapus Promo Toko "${promoName}"?\n\nDiskon akan dihentikan dan harga produk kembali normal. Aksi ini tidak bisa di-undo.`,
    );
    if (!confirmed) return;

    setDeleting(true);
    try {
      const res = await fetch(`/api/admin/discounts/promo-toko/${promoId}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const json = await res.json().catch(() => null);
        alert(json?.error ?? "Gagal menghapus promo. Coba lagi.");
        return;
      }
      router.refresh();
    } catch {
      alert("Gagal menghapus promo. Periksa koneksi.");
    } finally {
      setDeleting(false);
    }
  }

  return (
    <button
      type="button"
      onClick={handleDelete}
      disabled={deleting}
      className="text-sm font-semibold text-red-600 hover:text-red-700 disabled:opacity-50"
    >
      {deleting ? "Menghapus..." : "Hapus"}
    </button>
  );
}
