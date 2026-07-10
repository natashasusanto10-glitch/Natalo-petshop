"use client";

/**
 * Tombol "Batalkan order" + native confirm dialog.
 *
 * Kenapa wrapper client component:
 * - Server action `markAsCancelled` sekarang otomatis kredit refund ke
 *   Saldo Refund user. Tanpa konfirmasi, admin bisa mis-click → nominal
 *   nyangkut + customer kebingungan saldo tiba-tiba bertambah.
 * - Dialog kasih preview NOMINAL yang akan di-refund supaya admin verify
 *   sebelum eksekusi. Dipre-compute dari order.total − totalRefunded yg
 *   passed dari server component.
 *
 * Pakai window.confirm() (native) supaya tidak butuh modal library —
 * keep dependency minimal. Kalau nanti mau styled modal, ganti tinggal
 * import komponen Dialog.
 */
import { useState } from "react";
import { Button } from "@/components/admin/ui";

type Props = {
  action: () => Promise<void>;
  /** Total order — basis hitungan refund. */
  orderTotal: number;
  /** Sum refund CREDITED sebelumnya — kurangkan dari total. */
  alreadyRefunded: number;
  /** Saldo Refund yang user pakai bayar — bakal di-reverse (separate). */
  refundBalanceUsed: number;
  /**
   * paymentStatus order. Kalau bukan "PAID", auto-refund tidak akan jalan
   * (cancel cuma stock/voucher rollback) — pesan dialog disesuaikan.
   */
  paymentStatus: string;
  orderNumber: string;
};

function formatRp(n: number): string {
  return `Rp${new Intl.NumberFormat("id-ID").format(Math.max(0, n))}`;
}

export default function CancelOrderButton({
  action,
  orderTotal,
  alreadyRefunded,
  refundBalanceUsed,
  paymentStatus,
  orderNumber,
}: Props) {
  const [submitting, setSubmitting] = useState(false);

  // Pre-compute estimasi nominal yang akan di-refund. Logic mirror dengan
  // markAsCancelled server action — kalau di sini meleset 1-2 rupiah dgn
  // server, gpp karena server-side yang otoritatif. Tujuan dialog cuma
  // kasih order of magnitude ke admin.
  const willAutoRefund = paymentStatus === "PAID"
    ? Math.max(0, orderTotal - alreadyRefunded)
    : 0;

  async function handleClick() {
    const parts: string[] = [
      `Batalkan order #${orderNumber}?`,
      "",
    ];

    if (willAutoRefund > 0) {
      parts.push(
        `• ${formatRp(willAutoRefund)} akan OTOMATIS dikembalikan ke Saldo Refund customer`,
      );
    } else if (paymentStatus === "PAID") {
      parts.push("• Tidak ada nominal yang akan di-refund (sudah full-refund sebelumnya)");
    } else {
      parts.push("• Customer belum bayar — tidak ada refund yang perlu diproses");
    }

    if (refundBalanceUsed > 0) {
      parts.push(`• ${formatRp(refundBalanceUsed)} saldo yang dipakai bayar akan dibalikin ke wallet`);
    }
    parts.push("• Stock produk akan dikembalikan");
    parts.push("• Voucher (kalau ada) akan dibebaskan");
    parts.push("");
    parts.push("Aksi ini TIDAK BISA DI-UNDO. Lanjutkan?");

    const ok = window.confirm(parts.join("\n"));
    if (!ok) return;

    setSubmitting(true);
    try {
      await action();
    } catch (err) {
      // Server action throw → biasanya status guard (SHIPPED/DELIVERED).
      // Tampilkan ke admin supaya tahu kenapa gagal.
      const msg = err instanceof Error ? err.message : "Gagal membatalkan order.";
      window.alert(msg);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Button
      type="button"
      onClick={handleClick}
      disabled={submitting}
      variant="dangerSoft"
      fullWidth
    >
      {submitting ? "Membatalkan..." : "Batalkan order"}
    </Button>
  );
}
