"use client";

/**
 * Quick action per-item card: "Tandai kosong" button + inline expandable
 * form. Admin tap → input qty pcs yang missing → submit otomatis create
 * RefundCase + credit wallet (server action `markItemPartiallyOutOfStock`).
 *
 * UX flow:
 *  1. Inline collapsed button "Tandai kosong" warna amber per item.
 *  2. Tap → expand inline panel di bawah item card:
 *     - Qty input (default = max item.quantity)
 *     - Live preview "Refund: Rp X" auto-calc (net-of-voucher kalau ada)
 *     - Note input opsional (default "X pcs kosong saat packing")
 *  3. Submit → server action fire-and-forget, page revalidates.
 *
 * Vs RefundFormClient (full form):
 *  - RefundFormClient = manual flow, admin pilih item + qty + mode +
 *    reason + override. Bagus buat kasus kompleks.
 *  - ItemOutOfStockButton = 1-click happy path untuk "barang kosong saat
 *    packing" — auto-fill semua, admin tinggal confirm qty + submit.
 */
import { useState, useMemo } from "react";

function formatRupiah(n: number): string {
  return `Rp${new Intl.NumberFormat("id-ID").format(Math.max(0, Math.round(n)))}`;
}

export default function ItemOutOfStockButton({
  itemId,
  itemName,
  itemPrice,
  itemQuantity,
  orderSubtotal,
  orderProductDiscount,
  action,
}: {
  itemId: string;
  itemName: string;
  itemPrice: number;
  itemQuantity: number;
  orderSubtotal: number;
  orderProductDiscount: number;
  action: (formData: FormData) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const [missingQty, setMissingQty] = useState<number>(itemQuantity);
  const [note, setNote] = useState<string>("");

  const discountRatio = useMemo(() => {
    if (orderSubtotal <= 0) return 0;
    return Math.min(1, orderProductDiscount / orderSubtotal);
  }, [orderSubtotal, orderProductDiscount]);

  const gross = itemPrice * missingQty;
  const net = Math.round(gross * (1 - discountRatio));
  const hasVoucher = discountRatio > 0;

  if (!expanded) {
    return (
      <button
        type="button"
        onClick={() => setExpanded(true)}
        className="rounded-md border border-amber-300 bg-amber-50 px-2.5 py-1 text-[11px] font-semibold text-amber-800 hover:bg-amber-100"
      >
        Tandai kosong
      </button>
    );
  }

  return (
    <form
      action={action}
      className="mt-2 w-full space-y-2 rounded-lg border-2 border-amber-200 bg-amber-50 p-3"
    >
      <input type="hidden" name="itemId" value={itemId} />

      <div className="flex items-center gap-2">
        <span className="text-[11px] font-bold uppercase text-amber-800">
          Item kosong saat packing
        </span>
        <button
          type="button"
          onClick={() => setExpanded(false)}
          className="ml-auto text-[11px] text-zinc-500 hover:text-zinc-700"
        >
          Batal
        </button>
      </div>

      <div>
        <label className="block text-xs font-semibold text-zinc-700">
          Berapa pcs yang kosong?
        </label>
        <div className="mt-1 flex items-center gap-2">
          <input
            type="number"
            name="missingQty"
            min={1}
            max={itemQuantity}
            step={1}
            required
            value={missingQty}
            onChange={(e) => {
              const v = parseInt(e.target.value, 10);
              setMissingQty(Number.isFinite(v) ? v : 0);
            }}
            className="w-20 rounded-md border border-zinc-300 px-2.5 py-1.5 text-sm"
          />
          <span className="text-xs text-zinc-600">
            dari {itemQuantity} pcs total
          </span>
        </div>
      </div>

      {/* Live preview */}
      {missingQty > 0 && (
        <div className="rounded-md bg-white px-2.5 py-2 text-xs">
          <div className="flex items-center justify-between">
            <span className="text-zinc-600">
              {missingQty} × {formatRupiah(itemPrice)}
            </span>
            <span className="font-semibold text-zinc-900">
              {formatRupiah(gross)}
            </span>
          </div>
          {hasVoucher && (
            <>
              <div className="mt-0.5 flex items-center justify-between text-[11px] text-amber-700">
                <span>− Alokasi voucher ({(discountRatio * 100).toFixed(1)}%)</span>
                <span>−{formatRupiah(gross - net)}</span>
              </div>
              <div className="mt-0.5 border-t border-zinc-200 pt-0.5 flex items-center justify-between text-blue-900">
                <span className="font-semibold">Refund net</span>
                <span className="font-black">{formatRupiah(net)}</span>
              </div>
            </>
          )}
          {!hasVoucher && (
            <div className="mt-0.5 flex items-center justify-between text-blue-900">
              <span className="font-semibold">Refund</span>
              <span className="font-black">{formatRupiah(net)}</span>
            </div>
          )}
        </div>
      )}

      {/* Optional custom note (default auto-fill di server) */}
      <details className="text-xs">
        <summary className="cursor-pointer text-zinc-600">
          Catatan custom (opsional)
        </summary>
        <textarea
          name="adminNote"
          maxLength={500}
          rows={2}
          placeholder="Default: 'X pcs nama-item kosong saat packing.'"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          className="mt-1 w-full rounded-md border border-zinc-300 px-2.5 py-1.5 text-xs"
        />
      </details>

      <button
        type="submit"
        disabled={missingQty <= 0 || missingQty > itemQuantity}
        className="w-full rounded-md bg-amber-600 px-3 py-2 text-sm font-bold text-white hover:bg-amber-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
      >
        Refund {formatRupiah(net)} ke Saldo
      </button>
    </form>
  );
}
