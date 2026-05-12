"use client";

import { BottomSheet } from "@/components/BottomSheet";
import { formatRupiah } from "@/lib/format";

export type Rate = {
  courier_name: string;
  courier_code: string;
  courier_service_name: string;
  courier_service_code: string;
  service_type: string;          // instant|same_day|next_day|regular|economy
  price: number;
  duration: string;
  available: boolean;
  unavailable_reason?: string;
};

interface Props {
  open: boolean;
  onClose: () => void;
  rates: Rate[];
  loading: boolean;
  error?: string;
  selected: Rate | null;
  onSelect: (rate: Rate) => void;
  /** Optional: discount/voucher gratis ongkir aktif → harga di-coret, tampil Rp0 */
  freeShipping?: boolean;
}

const GROUPS: {
  key: string;
  serviceTypes: string[];
  label: string;
  icon: string;
  hint: string;
}[] = [
  { key: "instant",  serviceTypes: ["instant"],            label: "Instant",  icon: "🚀", hint: "Estimasi jam ini" },
  { key: "same_day", serviceTypes: ["same_day"],           label: "Same Day", icon: "📦", hint: "Estimasi hari ini" },
  { key: "regular",  serviceTypes: ["regular", "next_day"], label: "Reguler",  icon: "🚛", hint: "Estimasi 1-3 hari" },
  { key: "economy",  serviceTypes: ["economy"],            label: "Ekonomi",  icon: "📫", hint: "Estimasi 3-7 hari" },
];

export function MetodePengiriman({
  open,
  onClose,
  rates,
  loading,
  error,
  selected,
  onSelect,
  freeShipping = false,
}: Props) {
  // Group rates by service_type
  const groups = GROUPS.map((g) => ({
    ...g,
    items: rates.filter(
      (r) => g.serviceTypes.includes(r.service_type) && r.available
    ),
  })).filter((g) => g.items.length > 0);

  const disabledRates = rates.filter((r) => !r.available);
  const noResult = !loading && !error && rates.length === 0;

  return (
    <BottomSheet
      open={open}
      onClose={onClose}
      title="🚚 Pilih Pengiriman"
      footer={
        selected ? (
          <button
            onClick={onClose}
            className="w-full rounded-full bg-natalo-600 py-3 text-sm font-bold text-white hover:bg-natalo-700"
          >
            Pakai {selected.courier_name} {selected.courier_service_name}
          </button>
        ) : (
          <button
            onClick={onClose}
            className="w-full rounded-full bg-zinc-100 py-3 text-sm font-bold text-zinc-500"
            disabled
          >
            Pilih salah satu pengiriman
          </button>
        )
      }
    >
      {/* Loading */}
      {loading && (
        <div className="space-y-3">
          {[1, 2, 3, 4].map((i) => (
            <div
              key={i}
              className="h-16 animate-pulse rounded-2xl bg-zinc-100"
            />
          ))}
        </div>
      )}

      {/* Error */}
      {error && !loading && (
        <div className="rounded-2xl bg-red-50 p-5 text-center">
          <p className="text-2xl">⚠️</p>
          <p className="mt-2 text-sm font-semibold text-red-700">{error}</p>
        </div>
      )}

      {/* No result */}
      {noResult && (
        <div className="rounded-2xl bg-zinc-50 p-5 text-center">
          <p className="text-2xl">📭</p>
          <p className="mt-2 text-sm font-semibold text-zinc-700">
            Tidak ada kurir yang tersedia untuk alamat ini.
          </p>
          <p className="mt-1 text-xs text-zinc-500">
            Coba pilih ulang kota/kecamatan dari daftar alamat.
          </p>
        </div>
      )}

      {/* Group list */}
      {!loading && !error && groups.length > 0 && (
        <div className="space-y-5">
          {groups.map((g) => (
            <section key={g.key}>
              <h3 className="mb-2 flex items-center gap-2 text-sm font-bold text-zinc-700">
                <span>{g.icon}</span>
                <span>{g.label}</span>
                <span className="text-xs font-normal text-zinc-400">
                  · {g.hint}
                </span>
              </h3>
              <div className="space-y-2">
                {g.items.map((rate) => {
                  const isSelected =
                    selected?.courier_code === rate.courier_code &&
                    selected?.courier_service_code === rate.courier_service_code;
                  return (
                    <button
                      key={`${rate.courier_code}-${rate.courier_service_code}`}
                      type="button"
                      onClick={() => {
                        onSelect(rate);
                      }}
                      className={`flex w-full items-center justify-between gap-3 rounded-2xl border p-4 text-left transition ${
                        isSelected
                          ? "border-natalo-600 bg-natalo-50"
                          : "border-zinc-200 bg-white hover:border-natalo-300"
                      }`}
                    >
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <CourierLogo code={rate.courier_code} />
                          <p className="font-bold text-zinc-950">
                            {rate.courier_name}
                          </p>
                          <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-[10px] font-bold text-zinc-600">
                            {rate.courier_service_name}
                          </span>
                        </div>
                        <p className="mt-1 text-xs text-zinc-500">
                          {rate.duration}
                        </p>
                      </div>
                      <div className="shrink-0 text-right">
                        {freeShipping ? (
                          <>
                            <p className="text-xs text-zinc-400 line-through">
                              {formatRupiah(rate.price)}
                            </p>
                            <p className="text-base font-black text-green-600">
                              GRATIS
                            </p>
                          </>
                        ) : (
                          <p className="font-black text-natalo-600">
                            {formatRupiah(rate.price)}
                          </p>
                        )}
                        {isSelected && (
                          <p className="mt-1 text-xs font-bold text-natalo-700">
                            ✓ Dipilih
                          </p>
                        )}
                      </div>
                    </button>
                  );
                })}
              </div>
            </section>
          ))}
        </div>
      )}

      {/* Disabled section */}
      {!loading && !error && disabledRates.length > 0 && (
        <section className="mt-6">
          <h3 className="mb-2 flex items-center gap-2 text-sm font-bold text-zinc-400">
            <span>❌</span>
            <span>Tidak Tersedia</span>
          </h3>
          <div className="space-y-2">
            {disabledRates.map((rate) => (
              <div
                key={`d-${rate.courier_code}-${rate.courier_service_code}`}
                className="rounded-2xl border border-dashed border-zinc-200 p-4 opacity-60"
              >
                <div className="flex items-center gap-2">
                  <CourierLogo code={rate.courier_code} />
                  <p className="font-semibold text-zinc-700">
                    {rate.courier_name}
                  </p>
                  <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-[10px] font-bold text-zinc-500">
                    {rate.courier_service_name}
                  </span>
                </div>
                <p className="mt-1 text-xs text-zinc-500">
                  {rate.unavailable_reason ?? "Tidak tersedia"}
                </p>
              </div>
            ))}
          </div>
        </section>
      )}
    </BottomSheet>
  );
}

// Logo placeholder berdasarkan courier_code
function CourierLogo({ code }: { code: string }) {
  const map: Record<string, { bg: string; text: string; label: string }> = {
    jne:      { bg: "bg-red-100",    text: "text-red-700",    label: "JNE" },
    jnt:      { bg: "bg-red-100",    text: "text-red-700",    label: "J&T" },
    sicepat:  { bg: "bg-natalo-100", text: "text-natalo-800", label: "SiCepat" },
    anteraja: { bg: "bg-cyan-100",   text: "text-cyan-700",   label: "Antar" },
    gojek:    { bg: "bg-green-100",  text: "text-green-700",  label: "Gojek" },
    grab:     { bg: "bg-emerald-100",text: "text-emerald-700",label: "Grab" },
    paxel:    { bg: "bg-purple-100", text: "text-purple-700", label: "Paxel" },
    ninja:    { bg: "bg-pink-100",   text: "text-pink-700",   label: "Ninja" },
    pos:      { bg: "bg-amber-100",  text: "text-amber-700",  label: "Pos" },
  };
  const s = map[code.toLowerCase()] ?? {
    bg: "bg-zinc-100",
    text: "text-zinc-600",
    label: code.slice(0, 4).toUpperCase(),
  };
  return (
    <span
      className={`inline-flex h-6 min-w-[40px] shrink-0 items-center justify-center rounded px-1.5 text-[10px] font-black uppercase ${s.bg} ${s.text}`}
    >
      {s.label}
    </span>
  );
}
