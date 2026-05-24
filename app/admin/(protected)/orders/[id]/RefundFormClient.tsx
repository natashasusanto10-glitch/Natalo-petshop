"use client";

/**
 * Client-side form untuk admin issue refund. Auto-calc nominal dari
 * item + qty supaya admin tidak perlu hitung manual `qty × harga`,
 * plus auto-allocate voucher diskon proportional kalau order pakai
 * voucher (refund net-of-voucher) → admin tidak perlu hitung manual.
 *
 * Voucher allocation logic:
 *  - Ratio diskon = order.productDiscount / order.subtotal
 *    (e.g. order 3.252.000 dengan voucher 651.000 → ratio 20%)
 *  - Item refund net = qty × price × (1 - ratio)
 *    (e.g. 3 × 542.000 × (1 - 20%) = 1.300.800)
 *  - Asumsi voucher applied PROPORTIONAL ke semua item. Kalau voucher
 *    item-specific (eligibleProductIds), admin perlu Override manual
 *    karena server schema belum track per-item voucher allocation.
 *
 * Flow:
 *  1. Admin pilih item dari dropdown.
 *  2. Input qty pcs yang missing.
 *  3. UI auto-show 2 nilai: Gross (qty × price) + Net (after voucher).
 *  4. Kalau order pakai voucher → default ke Net (recommended).
 *     Kalau gak ada voucher → cuma Gross (no choice needed).
 *  5. Toggle "Override nominal manual" untuk kasus kompleks.
 *  6. Submit via server action — kirim hidden `amount` field.
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
  orderSubtotal,
  orderProductDiscount,
  orderShippingFee,
  orderShippingDiscount,
}: {
  items: RefundFormItem[];
  action: (formData: FormData) => void;
  orderSubtotal: number;
  orderProductDiscount: number;
  orderShippingFee: number;
  orderShippingDiscount: number;
}) {
  const [itemId, setItemId] = useState<string>("");
  const [refundQty, setRefundQty] = useState<number>(0);
  const [refundMode, setRefundMode] = useState<"net" | "gross">("net");
  const [manualOverride, setManualOverride] = useState<boolean>(false);
  const [manualAmount, setManualAmount] = useState<string>("");
  const [reason, setReason] = useState<string>("OUT_OF_STOCK");
  const [adminNote, setAdminNote] = useState<string>("");

  const selectedItem = useMemo(
    () => items.find((it) => it.id === itemId) ?? null,
    [items, itemId],
  );

  // Diskon ratio — % of subtotal yang ke-cover voucher.
  // Cuma productDiscount karena shipping discount terpisah (gak relate
  // ke per-item refund). Kalau subtotal 0 (defensive), ratio 0.
  const discountRatio = useMemo(() => {
    if (orderSubtotal <= 0) return 0;
    return Math.min(1, orderProductDiscount / orderSubtotal);
  }, [orderSubtotal, orderProductDiscount]);

  const hasProductVoucher = orderProductDiscount > 0;

  // Gross = qty × harga item original.
  const grossAmount = useMemo(() => {
    if (!selectedItem) return 0;
    const qty = Math.max(0, Math.floor(refundQty));
    return selectedItem.price * qty;
  }, [selectedItem, refundQty]);

  // Net = gross - voucher allocation proportional.
  // Round ke integer karena Rupiah gak ada desimal.
  const netAmount = useMemo(() => {
    return Math.round(grossAmount * (1 - discountRatio));
  }, [grossAmount, discountRatio]);

  const voucherAllocation = grossAmount - netAmount;

  // Default amount: net kalau ada voucher, gross kalau gak.
  const computedAmount = hasProductVoucher && refundMode === "net"
    ? netAmount
    : grossAmount;

  const effectiveAmount = manualOverride
    ? parseInt(manualAmount, 10) || 0
    : computedAmount;

  const requireManual = !selectedItem;

  const handleItemChange = (newItemId: string) => {
    setItemId(newItemId);
    const next = items.find((it) => it.id === newItemId);
    setRefundQty(next ? next.quantity : 0);
    setManualOverride(false);
  };

  const canSubmit = effectiveAmount > 0 && !!reason;

  return (
    <form action={action} className="mt-3 space-y-3 text-sm">
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
        </div>
      )}

      {/* Live calc preview — gross + net (voucher allocation) */}
      {selectedItem && refundQty > 0 && !manualOverride && (
        <div className="space-y-2">
          {/* Calc breakdown */}
          <div className="rounded-lg bg-blue-50 px-3 py-2.5 text-xs">
            <div className="flex items-center justify-between">
              <span className="text-zinc-700">
                {refundQty} × {formatRupiah(selectedItem.price)}
              </span>
              <span className="font-bold text-zinc-900">
                {formatRupiah(grossAmount)}
              </span>
            </div>
            {hasProductVoucher && (
              <>
                <div className="mt-1 flex items-center justify-between text-amber-700">
                  <span>
                    − Alokasi voucher ({(discountRatio * 100).toFixed(1)}%)
                  </span>
                  <span className="font-semibold">
                    −{formatRupiah(voucherAllocation)}
                  </span>
                </div>
                <div className="mt-1 border-t border-blue-200 pt-1.5 flex items-center justify-between text-blue-900">
                  <span className="font-semibold">Net (setelah voucher)</span>
                  <span className="font-black">
                    {formatRupiah(netAmount)}
                  </span>
                </div>
              </>
            )}
          </div>

          {/* Mode picker — gross vs net (cuma kalau ada voucher) */}
          {hasProductVoucher && (
            <div className="rounded-lg border border-zinc-200 bg-white p-2.5">
              <p className="text-[11px] font-semibold uppercase text-zinc-500">
                Pilih nominal yang di-refund
              </p>
              <div className="mt-1.5 space-y-1.5">
                <label className="flex cursor-pointer items-start gap-2 rounded-md p-1.5 hover:bg-zinc-50">
                  <input
                    type="radio"
                    name="refundModeRadio"
                    value="net"
                    checked={refundMode === "net"}
                    onChange={() => setRefundMode("net")}
                    className="mt-0.5 h-4 w-4 text-blue-600"
                  />
                  <div className="flex-1">
                    <p className="text-xs font-semibold text-zinc-900">
                      Net — {formatRupiah(netAmount)}{" "}
                      <span className="ml-1 rounded bg-emerald-100 px-1.5 py-0.5 text-[10px] font-bold text-emerald-700">
                        DIREKOMENDASIKAN
                      </span>
                    </p>
                    <p className="mt-0.5 text-[11px] text-zinc-500">
                      Jumlah yang user actually bayar untuk item ini
                      (sudah dikurangi alokasi voucher proporsional).
                    </p>
                  </div>
                </label>
                <label className="flex cursor-pointer items-start gap-2 rounded-md p-1.5 hover:bg-zinc-50">
                  <input
                    type="radio"
                    name="refundModeRadio"
                    value="gross"
                    checked={refundMode === "gross"}
                    onChange={() => setRefundMode("gross")}
                    className="mt-0.5 h-4 w-4 text-blue-600"
                  />
                  <div className="flex-1">
                    <p className="text-xs font-semibold text-zinc-900">
                      Gross — {formatRupiah(grossAmount)}
                    </p>
                    <p className="mt-0.5 text-[11px] text-zinc-500">
                      Harga penuh item tanpa potong voucher. Pakai
                      kalau voucher item-specific (gak apply ke item
                      ini) atau pakai goodwill compensation.
                    </p>
                  </div>
                </label>
              </div>
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
            disabled={requireManual}
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
              Untuk refund seluruh order, voucher item-specific, atau
              kasus khusus yang gak fit ke gross/net calculation.
            </p>
            {!requireManual && (
              <div className="mt-2 grid grid-cols-2 gap-2 text-[11px]">
                <button
                  type="button"
                  onClick={() => setManualAmount(String(grossAmount))}
                  className="rounded border border-zinc-300 bg-white px-2 py-1 hover:bg-zinc-50"
                >
                  Pakai Gross ({formatRupiah(grossAmount)})
                </button>
                <button
                  type="button"
                  onClick={() => setManualAmount(String(netAmount))}
                  className="rounded border border-zinc-300 bg-white px-2 py-1 hover:bg-zinc-50"
                  disabled={!hasProductVoucher}
                >
                  Pakai Net ({formatRupiah(netAmount)})
                </button>
              </div>
            )}
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
          {/* Helper note context */}
          {!manualOverride && selectedItem && hasProductVoucher && (
            <p className="mt-1 text-[11px] text-zinc-600">
              Mode: <span className="font-bold">{refundMode === "net" ? "Net (setelah voucher)" : "Gross (tanpa voucher)"}</span>
            </p>
          )}
        </div>
      )}

      {/* Shipping discount info — read-only, gak affect product refund */}
      {orderShippingDiscount > 0 && (
        <p className="text-[11px] text-zinc-500">
          ℹ️ Order ini juga pakai voucher ongkir ({formatRupiah(orderShippingDiscount)}
          ). Voucher ongkir tidak alokasi ke per-item — refund-nya
          hitung manual via Override kalau perlu (e.g. cancel seluruh
          order = refund total = ongkir + barang).
        </p>
      )}

      <button
        type="submit"
        disabled={!canSubmit}
        className="w-full rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
      >
        Kredit Saldo Refund
      </button>

      {/* Order context untuk debugging admin */}
      <details className="text-[11px] text-zinc-500">
        <summary className="cursor-pointer">Lihat data order (untuk verifikasi)</summary>
        <dl className="mt-1.5 grid grid-cols-2 gap-x-3 gap-y-0.5 rounded bg-zinc-50 p-2">
          <dt>Subtotal:</dt>
          <dd className="text-right font-mono">{formatRupiah(orderSubtotal)}</dd>
          <dt>Diskon Produk:</dt>
          <dd className="text-right font-mono">−{formatRupiah(orderProductDiscount)}</dd>
          <dt>Ongkir:</dt>
          <dd className="text-right font-mono">{formatRupiah(orderShippingFee)}</dd>
          <dt>Diskon Ongkir:</dt>
          <dd className="text-right font-mono">−{formatRupiah(orderShippingDiscount)}</dd>
          {hasProductVoucher && (
            <>
              <dt className="text-amber-700">Voucher ratio:</dt>
              <dd className="text-right font-mono text-amber-700">
                {(discountRatio * 100).toFixed(2)}%
              </dd>
            </>
          )}
        </dl>
      </details>
    </form>
  );
}
