"use client";

import { useEffect, useState } from "react";
import { NumberInput } from "./ui/NumberInput";
import { formatRupiah } from "@/lib/format";

export function VoucherDiscountFields({
  defaultType = "PUBLIC_PRODUCT_DISCOUNT", defaultPercent, defaultAmount,
  defaultCap, defaultMinimum = 0,
}: {
  defaultType?: string; defaultPercent?: number | null; defaultAmount?: number | null;
  defaultCap?: number | null; defaultMinimum?: number;
}) {
  const [type, setType] = useState(defaultType);
  const [mode, setMode] = useState(defaultPercent ? "percent" : "amount");
  const [percent, setPercent] = useState(String(defaultPercent ?? ""));
  const [amount, setAmount] = useState(String(defaultAmount ?? (defaultType === "PUBLIC_FREE_SHIPPING" ? defaultCap : null) ?? ""));
  const [cap, setCap] = useState(String(defaultCap ?? ""));
  const [minimum, setMinimum] = useState(String(defaultMinimum));
  useEffect(() => {
    const apply = (event: Event) => {
      const d = (event as CustomEvent).detail;
      setType(d.type); setMode(d.discountPercent ? "percent" : "amount");
      setPercent(String(d.discountPercent ?? "")); setAmount(String(d.discountAmount ?? d.maxDiscountAmount ?? ""));
      setCap(String(d.maxDiscountAmount ?? "")); setMinimum(String(d.minimumOrder ?? 0));
    };
    window.addEventListener("voucher-suggestion", apply);
    return () => window.removeEventListener("voucher-suggestion", apply);
  }, []);
  const freeShipping = type === "PUBLIC_FREE_SHIPPING";
  const percentage = !freeShipping && mode === "percent";
  const exampleBase = Math.max(100000, Number(minimum) || 0);
  const exampleDiscount = percentage
    ? Math.min(exampleBase, Math.round(exampleBase * (Number(percent) || 0) / 100), cap ? Number(cap) : Infinity)
    : Math.min(exampleBase, Number(amount) || 0);
  const numberField = (id: string, label: string, value: string, change: (v: string) => void, required = false) => (
    <div><label htmlFor={id} className="block text-sm font-medium text-slate-700">{label}</label>
      <NumberInput id={id} value={value} onValueChange={change} required={required} pattern="[0-9.]+"
        className="mt-1 w-full rounded-xl border border-slate-300 px-4 py-3 text-sm" />
    </div>
  );
  return <section className="admin-section p-4 space-y-4 md:p-5" aria-label="Aturan diskon voucher">
    <div><label htmlFor="voucher-type" className="block text-sm font-medium text-slate-700">Tipe voucher</label>
      <select id="voucher-type" name="type" value={type} onChange={e => setType(e.target.value)} className="mt-1 w-full rounded-xl border border-slate-300 px-4 py-3 text-sm">
        <option value="PUBLIC_PRODUCT_DISCOUNT">Diskon produk publik</option><option value="PUBLIC_FREE_SHIPPING">Gratis ongkir publik</option>
        <option value="PRIVATE_MANUAL_CODE">Kode privat</option>
        {defaultType === "LOYALTY_POINT_CLAIM" && <option value="LOYALTY_POINT_CLAIM">Reward poin</option>}
      </select></div>
    {!freeShipping && <fieldset><legend className="text-sm font-medium text-slate-700">Bentuk diskon</legend>
      <div className="mt-2 flex gap-4">{[["amount", "Nominal"], ["percent", "Persentase"]].map(([key, label]) => <label key={key} className="flex min-h-11 items-center gap-2 text-sm"><input type="radio" checked={mode === key} onChange={() => setMode(key)} name="discountMode" value={key} />{label}</label>)}</div>
    </fieldset>}
    {percentage ? <div><label htmlFor="voucher-percent" className="block text-sm font-medium text-slate-700">Diskon (%)</label><input id="voucher-percent" type="text" inputMode="numeric" required pattern="[0-9]{1,3}" value={percent} onChange={e => setPercent(e.target.value)} className="mt-1 w-full rounded-xl border border-slate-300 px-4 py-3 text-sm" /><p className="mt-1 text-xs text-slate-500">1–100%. Potongan dibatasi maksimum diskon jika diisi.</p></div>
      : numberField("voucher-amount", freeShipping ? "Maksimum potongan ongkir" : "Diskon nominal", amount, setAmount, true)}
    {percentage && numberField("voucher-cap", "Maksimum diskon (opsional)", cap, setCap)}
    {numberField("voucher-minimum", "Minimum belanja", minimum, setMinimum, true)}
    <input type="hidden" name="discountPercent" value={percentage ? percent : ""} />
    <input type="hidden" name="discountAmount" value={percentage ? "" : amount} />
    <input type="hidden" name="maxDiscountAmount" value={percentage ? cap : ""} />
    <input type="hidden" name="minimumOrder" value={minimum} />
    <div className="rounded-xl bg-blue-50 p-3 text-sm text-blue-900" aria-live="polite">
      {freeShipping ? `Potongan ongkir hingga ${formatRupiah(Number(amount) || 0)}, mengikuti biaya ongkir pesanan.`
        : `Contoh belanja ${formatRupiah(exampleBase)}: potongan ${formatRupiah(exampleDiscount)}.`}
    </div>
  </section>;
}
