"use client";

import { useEffect, useRef, useState } from "react";

export type ShippingArea = {
  area_id: string;
  label: string;
  province_name: string;
  city_name: string;
  district_name: string;
  postal_code: string;
};

type Props = {
  selectedArea?: ShippingArea | null;
  onSelect: (area: ShippingArea) => void;
  onClear?: () => void;
  label?: string;
  required?: boolean;
  error?: string;
  help?: string;
};

const INPUT_CLASS =
  "mt-2 block w-full rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:text-zinc-400";

export function BiteshipAreaCombobox({
  selectedArea,
  onSelect,
  onClear,
  label = "Kota / Kecamatan",
  required = true,
  error,
  help,
}: Props) {
  const [query, setQuery] = useState(selectedArea?.label ?? "");
  const [areas, setAreas] = useState<ShippingArea[]>([]);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const latestRequest = useRef(0);
  const wrapperRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    setQuery(selectedArea?.label ?? "");
  }, [selectedArea?.area_id, selectedArea?.label]);

  useEffect(() => {
    function close(event: MouseEvent) {
      if (wrapperRef.current && !wrapperRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, []);

  useEffect(() => {
    const keyword = query.trim();
    if (selectedArea?.label === query) return;
    if (keyword.length < 3) {
      setAreas([]);
      setMessage(keyword.length === 0 ? "" : "Ketik minimal 3 huruf.");
      setLoading(false);
      return;
    }

    const requestId = latestRequest.current + 1;
    latestRequest.current = requestId;
    const controller = new AbortController();
    const timer = window.setTimeout(async () => {
      setLoading(true);
      setMessage("");
      try {
        const response = await fetch(`/api/shipping/areas?keyword=${encodeURIComponent(keyword)}`, {
          signal: controller.signal,
        });
        const data = (await response.json()) as { areas?: ShippingArea[]; message?: string };
        if (latestRequest.current !== requestId) return;
        const nextAreas = Array.isArray(data.areas) ? data.areas : [];
        setAreas(nextAreas);
        setMessage(nextAreas.length === 0 ? data.message ?? "Area tidak ditemukan." : "");
        setOpen(true);
      } catch (err) {
        if ((err as Error).name !== "AbortError") {
          setAreas([]);
          setMessage("Pencarian area belum bisa dipakai. Coba lagi.");
        }
      } finally {
        if (latestRequest.current === requestId) setLoading(false);
      }
    }, 500);

    return () => {
      controller.abort();
      window.clearTimeout(timer);
    };
  }, [query, selectedArea?.label]);

  function handleInput(value: string) {
    setQuery(value);
    setOpen(true);
    if (selectedArea && value !== selectedArea.label) {
      onClear?.();
    }
  }

  return (
    <div className="relative" ref={wrapperRef}>
      <label className="block text-sm font-bold text-zinc-800">
        {label}
        {required && <span className="ml-1 text-natalo-600">*</span>}
      </label>
      <input
        type="search"
        value={query}
        onChange={(event) => handleInput(event.target.value)}
        onFocus={() => setOpen(true)}
        placeholder="Cari kecamatan/kota, contoh: Sukmajaya Depok"
        autoComplete="off"
        className={INPUT_CLASS}
      />
      {help && !error && <p className="mt-1 text-xs font-medium text-zinc-500">{help}</p>}
      {error && <p className="mt-1 text-xs font-semibold text-red-500">{error}</p>}
      {selectedArea && (
        <div className="mt-2 rounded-xl border border-emerald-100 bg-emerald-50 px-3 py-2 text-xs font-semibold text-emerald-800">
          Area Biteship terpilih: {selectedArea.label}
        </div>
      )}

      {open && (loading || message || areas.length > 0) && !selectedArea && (
        <div className="absolute z-40 mt-1 w-full overflow-hidden rounded-xl border border-zinc-200 bg-white shadow-xl">
          {loading && (
            <div className="px-4 py-3 text-sm font-semibold text-zinc-500">
              Mencari area...
            </div>
          )}
          {!loading && areas.length > 0 && (
            <div className="max-h-72 overflow-y-auto">
              {areas.map((area) => (
                <button
                  key={area.area_id}
                  type="button"
                  onClick={() => {
                    onSelect(area);
                    setQuery(area.label);
                    setOpen(false);
                  }}
                  className="block w-full px-4 py-3 text-left text-sm transition hover:bg-natalo-50"
                >
                  <span className="block font-black text-zinc-900">{area.district_name}</span>
                  <span className="mt-0.5 block text-xs font-semibold text-zinc-500">
                    {area.city_name}, {area.province_name}. {area.postal_code}
                  </span>
                </button>
              ))}
            </div>
          )}
          {!loading && areas.length === 0 && message && (
            <div className="px-4 py-3 text-sm font-semibold text-zinc-500">
              {message}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
