"use client";

/**
 * Client-side form untuk admin issue refund. Auto-calc nominal dari
 * item + qty supaya admin tidak perlu hitung manual `qty × harga`.
 *
 * Flow:
 *  1. Admin pilih item dari dropdown (single item refund) atau
 *     "Seluruh order" (whole order refund).
 *  2. Kalau pilih item → input qty pcs yang missing (default = full qty).
 *  3. Live preview: "3 × Rp542.000 = Rp1.626.000".
 *  4. Toggle "Override nominal manual" untuk kasus kompleks (voucher
 *     proporsional, special discount, partial price item).
 *  5. Submit via server action — kirim hidden `amount` field (computed
 *     atau manual override).
 *
 * Catatan voucher: kalau order pake voucher, qty × harga = gross item
 * cost. User actually paid less karena voucher allocate sebagian
 * diskon ke item ini. Admin perlu adjust manual via "Override" kalau
 * mau refund net-of-voucher. Future: auto-compute voucher allocation
 * proportional dari order.discount / order.subtotal.
 */
import { useState, useMemo } from "react";

const reasons = [
  { value: "OUT_OF_STOCK", label: "Produk kosong" },
  { value: "PARTIAL_CANCEL", label: "Dibatalkan sebagian" },
  { value: "RETURN_APPROVED", label: "Return disetujui" },
  { value: "ORDER_CANCELLED", label: "Order dibatalkan" },
  { value: "OTHER", label: "Lainnya" },
] as const;

export type RefundFormItem = {
  id: string;
  name: string;
  quantity: number;
  price: number;
};

function formatRupiah(n: number): string {
  return `Rp${new Intl.NumberFormat("id-ID").format(Math.max(0, Math.round(n)))}`;
}

export default function RefundFormClient({
  items,
  action,
  orderHasVoucher,
}: {
  items: RefundFormItem[];
  action: (formData: FormData) => void;
  /** True kalau order pakai voucher → tampilkan warning + saran override */
  orderHasVoucher: boolean;
}) {
  const [itemId, setItemId] = useState<string>("");
  const [refundQty, setRefundQty] = useState<number>(0);
  const [manualOverride, setManualOverride] = useState<boolean>(false);
  const [manualAmount, setManualAmount] = useState<string>("");
  const [reason, setReason] = useState<string>("OUT_OF_STOCK");
  const [adminNote, setAdminNote] = useState<string>("");

  const selectedItem = useMemo(
    () => items.find((it) => it.id === itemId) ?? null,
    [items, itemId],
  );

  // Auto-compute amount: kalau ada item + qty, hitung qty × price.
  // Kalau "Seluruh order" (no itemId), wajib manual override.
  const computedAmount = useMemo(() => {
    if (!selectedItem) return 0;
    const qty = Math.max(0, Math.floor(refundQty));
    return selectedItem.price * qty;
  }, [selectedItem, refundQty]);

  const effectiveAmount = manualOverride
    ? parseInt(manualAmount, 10) || 0
    : computedAmount;

  // Auto-enable manual override kalau pilih "Seluruh order" (no item-
  // based calc possible) — supaya admin gak stuck di nominal 0.
  const requireManual = !selectedItem;

  // Reset qty saat ganti item. Default ke full qty (asumsi seluruh item
  // di-refund — admin tinggal kurangi kalau partial).
  const handleItemChange = (newItemId: string) => {
    setItemId(newItemId);
    const next = items.find((it) => it.id === newItemId);
    setRefundQty(next ? next.quantity : 0);
    setManualOverride(false);
  };

  const canSubmit = effectiveAmount > 0 && !!reason;

  return (
    <form
      action={action}
      className="mt-3 space-y-3 text-sm"
    >
      {/* Item picker */}
      <div>
        <label className="block text-xs font-semibold text-zinc-700">
          Item yang di-refund
        </label>
        <select
          name="itemId"
          value={itemId}
          onChange={(e) => handleItemChange(e.target.value)}
          className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
        >
          <option value="">— Seluruh order (manual amount) —</option>
          {items.map((item) => (
            <option key={item.id} value={item.id}>
              {item.name} ({item.quantity}× {formatRupiah(item.price)})
            </option>
          ))}
        </select>
      </div>

      {/* Quantity input — hanya muncul kalau item terpilih */}
      {selectedItem && (
        <div>
          <label className="block text-xs font-semibold text-zinc-700">
            Berapa pcs yang di-refund?
          </label>
          <div className="mt-1 flex items-center gap-2">
            <input
              type="number"
              min={1}
              max={selectedItem.quantity}
              step={1}
              value={refundQty}
              onChange={(e) => {
                const v = parseInt(e.target.value, 10);
                setRefundQty(Number.isFinite(v) ? v : 0);
              }}
              className="w-24 rounded-lg border border-zinc-300 px-3 py-2 text-sm"
              disabled={manualOverride}
            />
            <span className="text-xs text-zinc-500">
              dari {selectedItem.quantity} pcs total
            </span>
          </div>

          {/* Live preview hitungan */}
          {!manualOverride && refundQty > 0 && (
            <div className="mt-2 rounded-lg bg-blue-50 px-3 py-2 text-xs">
              <p className="text-zinc-700">
                {refundQty} × {formatRupiah(selectedItem.price)} ={" "}
                <span className="font-bold text-blue-900">
                  {formatRupiah(computedAmount)}
                </span>
              </p>
              {orderHasVoucher && (
                <p className="mt-1 text-[11px] text-amber-700">
                  ⚠️ Order ini pakai voucher. Hitungan di atas = gross item
                  cost. Kalau mau refund net-of-voucher (jumlah yang
                  user actually bayar), aktifkan "Override nominal"
                  di bawah.
                </p>
              )}
            </div>
          )}
        </div>
      )}

      {/* Manual override toggle */}
      <div className="rounded-lg border border-zinc-200 bg-zinc-50 p-3">
        <label className="flex cursor-pointer items-center gap-2 text-xs font-semibold text-zinc-700">
          <input
            type="checkbox"
            checked={manualOverride}
            onChange={(e) => setManualOverride(e.target.checked)}
            disabled={requireManual} /* selalu manual kalau no item */
            className="h-4 w-4 rounded border-zinc-300 text-blue-600"
          />
          Override nominal manual{requireManual && " (wajib untuk seluruh order)"}
        </label>
        {(manualOverride || requireManual) && (
          <div className="mt-2">
            <input
              type="number"
              min={1}
              step={1}
              required
              placeholder="32000"
              value={manualAmount}
              onChange={(e) => setManualAmount(e.target.value)}
              className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
            />
            <p className="mt-1 text-[11px] text-zinc-500">
              Pakai ini untuk: refund seluruh order, voucher proporsional,
              atau kasus khusus lain.
            </p>
          </div>
        )}
      </div>

      {/* Hidden amount field — submitted ke server action */}
      <input type="hidden" name="amount" value={effectiveAmount} />

      {/* Reason */}
      <div>
        <label className="block text-xs font-semibold text-zinc-700">
          Alasan refund
        </label>
        <select
          name="reason"
          required
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
        >
          {reasons.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}
            </option>
          ))}
        </select>
      </div>

      {/* Admin note */}
      <div>
        <label className="block text-xs font-semibold text-zinc-700">
          Catatan untuk user (opsional)
        </label>
        <textarea
          name="adminNote"
          maxLength={500}
          rows={2}
          placeholder="Stok kosong saat packing, maaf ya!"
          value={adminNote}
          onChange={(e) => setAdminNote(e.target.value)}
          className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
        />
      </div>

      {/* Final amount confirm display */}
      {effectiveAmount > 0 && (
        <div className="rounded-lg border-2 border-blue-200 bg-blue-50 px-3 py-2.5">
          <p className="text-xs text-zinc-600">Total refund yang akan dikredit:</p>
          <p className="mt-0.5 text-lg font-black text-blue-900">
            {formatRupiah(effectiveAmount)}
          </p>
        </div>
      )}

      <button
        type="submit"
        disabled={!canSubmit}
        className="w-full rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
      >
        Kredit Saldo Refund
      </button>
    </form>
  );
}
