"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { formatRupiah } from "@/lib/format";
import type { RateOption } from "@/lib/shipping-rates";
import { useProductDetailState } from "./ProductDetailState";

type Address = {
  id: string; label: string | null; isMain: boolean; areaId: string | null;
  areaLabel: string | null; city: string | null; postalCode: string | null;
  latitude: number | null; longitude: number | null;
};
type Props = { name: string; price: number; weightGram: number; hasVariants: boolean };

export function ProductShippingPreview({ name, price, weightGram, hasVariants }: Props) {
  const variant = useProductDetailState()?.variant;
  const [addresses, setAddresses] = useState<Address[] | null>(null);
  const [addressId, setAddressId] = useState("");
  const [loginRequired, setLoginRequired] = useState(false);
  const [rates, setRates] = useState<RateOption[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [retry, setRetry] = useState(0);
  const address = addresses?.find(item => item.id === addressId);
  const needsVariant = hasVariants && !variant;

  useEffect(() => {
    const controller = new AbortController();
    setError(null);
    fetch("/api/addresses", { signal: controller.signal }).then(async response => {
      if (response.status === 401) { setLoginRequired(true); return; }
      if (!response.ok) throw new Error("Alamat gagal dimuat");
      const data = await response.json();
      if (controller.signal.aborted) return;
      const list: Address[] = data.addresses;
      setAddresses(list);
      setAddressId(current => list.some(item => item.id === current) ? current : (list.find(item => item.isMain) ?? list[0])?.id ?? "");
    }).catch(() => {
      if (!controller.signal.aborted) setError("Alamat gagal dimuat. Coba lagi.");
    });
    return () => controller.abort();
  }, [retry]);

  useEffect(() => {
    setRates([]);
    setExpanded(false);
    if (needsVariant || !address?.areaId) { setLoading(false); return; }
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    fetch("/api/shipping/rates", {
      method: "POST", signal: controller.signal,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        destinationAreaId: address.areaId, destinationPostalCode: address.postalCode,
        destinationLatitude: address.latitude, destinationLongitude: address.longitude,
        items: [{ name, price: variant?.price ?? price, weightGram: variant?.weightGram ?? weightGram, quantity: 1 }],
      }),
    }).then(async response => {
      const data = await response.json();
      if (!response.ok) throw new Error("Ongkir gagal dimuat");
      if (controller.signal.aborted) return;
      setRates((data.rates as RateOption[]).filter(rate => rate.available && rate.price > 0).sort((a,b) => a.price - b.price));
    }).catch(() => {
      if (!controller.signal.aborted) setError("Ongkir gagal dimuat. Coba lagi.");
    }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [address, needsVariant, name, price, weightGram, variant, retry]);

  return <section className="mt-4 border-y border-gray-100 py-3" aria-label="Pengiriman produk">
    <div className="flex items-start gap-3">
      <span aria-hidden="true" className="text-emerald-600">🚚</span>
      <div className="min-w-0 flex-1">
        <h2 className="text-sm font-semibold">Pengiriman</h2>
        {needsVariant ? <button type="button" className="mt-1 text-xs text-blue-600" onClick={() => document.getElementById("beli")?.scrollIntoView({ behavior: "smooth", block: "center" })}>Pilih varian untuk cek ongkir</button>
          : loginRequired ? <Link href="/member/login" className="mt-1 block text-xs text-blue-600">Masuk untuk cek ongkir</Link>
          : addresses?.length === 0 ? <Link href="/akun/alamat" className="mt-1 block text-xs text-blue-600">Atur alamat untuk cek ongkir</Link>
          : addresses && <>
            <label className="mt-1 block text-xs text-gray-500" htmlFor="product-shipping-address">Kirim ke</label>
            <select id="product-shipping-address" value={addressId} onChange={event => setAddressId(event.target.value)} className="mt-1 w-full rounded-md border border-gray-200 bg-white px-2 py-1.5 text-xs">
              {addresses.map(item => <option key={item.id} value={item.id}>{[item.label, item.areaLabel || item.city].filter(Boolean).join(" · ")}</option>)}
            </select>
            {!address?.areaId && <Link href="/akun/alamat" className="mt-1 block text-xs text-blue-600">Lengkapi alamat untuk cek ongkir</Link>}
          </>}
        {loading && <p role="status" className="mt-2 text-xs text-gray-500">Menghitung ongkir…</p>}
        {error && <button type="button" onClick={() => setRetry(value => value + 1)} className="mt-2 text-xs text-rose-600">{error}</button>}
        {!loading && !error && address?.areaId && !needsVariant && (rates.length ? <>
          <button type="button" onClick={() => setExpanded(value => !value)} aria-expanded={expanded} className="mt-2 text-left text-xs font-semibold text-emerald-700">Mulai {formatRupiah(rates[0].price)}{rates[0].duration ? ` · Estimasi ${rates[0].duration}` : ""} ›</button>
          {expanded && <ul className="mt-2 space-y-2 rounded-lg bg-gray-50 p-2">{rates.map(rate => <li key={`${rate.courier_code}-${rate.courier_service_code}`} className="flex justify-between gap-2 text-xs"><span>{rate.courier_name} {rate.courier_service_name}<span className="block text-gray-500">{rate.duration}</span></span><span>{formatRupiah(rate.price)}</span></li>)}</ul>}
          <p className="mt-1 text-[10px] text-gray-500">Estimasi untuk 1 produk. Pilihan dan potongan ongkir final ditentukan saat checkout.</p>
        </> : <p className="mt-2 text-xs text-gray-500">Pengiriman belum tersedia ke alamat ini.</p>)}
      </div>
      {addresses && addresses.length > 0 && <Link href="/akun/alamat" className="text-xs text-blue-600">Atur alamat</Link>}
    </div>
  </section>;
}
