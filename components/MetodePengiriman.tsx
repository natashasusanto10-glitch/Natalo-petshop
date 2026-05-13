"use client";

import { BottomSheet } from "@/components/BottomSheet";
import { formatRupiah } from "@/lib/format";
import { SHIPPING_ORIGIN_UNAVAILABLE_DETAIL } from "@/lib/shipping-messages";
import {
  SELF_PICKUP_METHOD,
  SELF_PICKUP_STORE,
  buildSelfPickupMapsUrl,
  isSelfPickupMethod,
} from "@/lib/self-pickup";

export type Rate = {
  courier_name: string;
  courier_code: string;
  courier_service_name: string;
  courier_service_code: string;
  service_type: string;
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
  freeShipping?: boolean;
}

export const SELF_PICKUP_RATE: Rate = {
  courier_name: "Ambil Sendiri di Toko",
  courier_code: SELF_PICKUP_METHOD,
  courier_service_name: "Gratis ongkir",
  courier_service_code: SELF_PICKUP_METHOD,
  service_type: "pickup",
  price: 0,
  duration: SELF_PICKUP_STORE.hours,
  available: true,
};

const GROUPS: {
  key: string;
  serviceTypes: string[];
  label: string;
  icon: string;
  hint: string;
}[] = [
  { key: "instant", serviceTypes: ["instant"], label: "Instant", icon: "EXP", hint: "Estimasi jam ini" },
  { key: "same_day", serviceTypes: ["same_day"], label: "Same Day", icon: "DAY", hint: "Estimasi hari ini" },
  { key: "regular", serviceTypes: ["regular", "next_day"], label: "Reguler", icon: "REG", hint: "Estimasi 1-3 hari" },
  { key: "economy", serviceTypes: ["economy"], label: "Ekonomi", icon: "ECO", hint: "Estimasi 3-7 hari" },
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
  const groups = GROUPS.map((g) => ({
    ...g,
    items: rates.filter(
      (r) => g.serviceTypes.includes(r.service_type) && r.available
    ),
  })).filter((g) => g.items.length > 0);

  const disabledRates = rates.filter((r) => !r.available);
  const noResult = !loading && !error && rates.length === 0;
  const selfPickupSelected = isSelfPickupMethod(selected?.courier_code);

  return (
    <BottomSheet
      open={open}
      onClose={onClose}
      title="Pilih metode pengiriman"
      footer={
        selected ? (
          <button
            type="button"
            onClick={onClose}
            className="w-full rounded-full bg-natalo-600 py-3 text-sm font-bold text-white hover:bg-natalo-700"
          >
            Pilih Metode
          </button>
        ) : (
          <button
            type="button"
            onClick={onClose}
            className="w-full rounded-full bg-zinc-100 py-3 text-sm font-bold text-zinc-500"
            disabled
          >
            Pilih salah satu metode
          </button>
        )
      }
    >
      <button
        type="button"
        onClick={() => onSelect(SELF_PICKUP_RATE)}
        className={`mb-4 w-full rounded-2xl border p-4 text-left transition ${
          selfPickupSelected
            ? "border-natalo-600 bg-natalo-50"
            : "border-zinc-200 bg-white hover:border-natalo-300"
        }`}
      >
        <div className="flex items-start gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-blue-50 text-xs font-black text-blue-700">
            SHOP
          </span>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <p className="font-black text-zinc-950">Ambil Sendiri di Toko</p>
              <span className="rounded-full bg-green-100 px-2 py-0.5 text-[10px] font-black text-green-700">
                Gratis ongkir
              </span>
            </div>
            <p className="mt-1 text-xs font-semibold text-blue-700">
              Self Pick Up - Gratis Ongkir
            </p>
            <p className="mt-2 text-sm text-zinc-600">
              Ambil pesanan langsung di toko yang telah dipilih.
            </p>
            <div className="mt-3 rounded-2xl bg-white/80 p-3 text-sm text-zinc-700">
              <p className="text-xs font-black text-zinc-500">Lokasi Toko</p>
              <p className="mt-1 font-bold text-zinc-950">{SELF_PICKUP_STORE.name}</p>
              <p>{SELF_PICKUP_STORE.addressLine}</p>
              <p>{SELF_PICKUP_STORE.area}</p>
              <p className="mt-2 text-xs font-bold text-zinc-500">
                Jam ambil: {SELF_PICKUP_STORE.hours}
              </p>
              <a
                href={buildSelfPickupMapsUrl()}
                target="_blank"
                rel="noreferrer"
                onClick={(event) => event.stopPropagation()}
                className="mt-3 inline-flex rounded-full border border-blue-200 px-3 py-1.5 text-xs font-black text-blue-700 hover:bg-blue-50"
              >
                Buka di Google Maps
              </a>
            </div>
            {selfPickupSelected && (
              <p className="mt-2 text-xs font-bold text-natalo-700">Dipilih</p>
            )}
          </div>
        </div>
      </button>

      {loading && (
        <div className="space-y-3">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="h-16 animate-pulse rounded-2xl bg-zinc-100" />
          ))}
        </div>
      )}

      {error && !loading && (
        <div className="rounded-2xl bg-amber-50 p-5 text-center">
          <span className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-amber-100 text-lg font-black text-amber-700">
            !
          </span>
          <p className="mt-3 text-sm font-black text-amber-900">
            Kurir belum tersedia untuk alamat ini
          </p>
          <p className="mt-1 text-sm font-semibold text-amber-800">{error}</p>
          <p className="mt-2 text-xs font-medium text-amber-700">
            Kamu tetap bisa memilih Ambil Sendiri di Toko tanpa ongkir.
            {error.includes("origin") ? ` ${SHIPPING_ORIGIN_UNAVAILABLE_DETAIL}` : ""}
          </p>
        </div>
      )}

      {noResult && (
        <div className="rounded-2xl bg-zinc-50 p-5 text-center">
          <p className="text-sm font-semibold text-zinc-700">
            Kurir belum tersedia untuk alamat ini.
          </p>
          <p className="mt-1 text-xs text-zinc-500">
            Kamu tetap bisa memilih Ambil Sendiri di Toko tanpa ongkir.
          </p>
        </div>
      )}

      {!loading && !error && groups.length > 0 && (
        <div className="space-y-5">
          {groups.map((g) => (
            <section key={g.key}>
              <h3 className="mb-2 flex items-center gap-2 text-sm font-bold text-zinc-700">
                <span className="rounded bg-zinc-100 px-1.5 py-0.5 text-[10px] font-black text-zinc-600">
                  {g.icon}
                </span>
                <span>{g.label}</span>
                <span className="text-xs font-normal text-zinc-400">
                  - {g.hint}
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
                      onClick={() => onSelect(rate)}
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
                            Dipilih
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

      {!loading && !error && disabledRates.length > 0 && (
        <section className="mt-6">
          <h3 className="mb-2 flex items-center gap-2 text-sm font-bold text-zinc-400">
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

function CourierLogo({ code }: { code: string }) {
  const map: Record<string, { bg: string; text: string; label: string }> = {
    jne: { bg: "bg-red-100", text: "text-red-700", label: "JNE" },
    jnt: { bg: "bg-red-100", text: "text-red-700", label: "J&T" },
    sicepat: { bg: "bg-natalo-100", text: "text-natalo-800", label: "SiCepat" },
    anteraja: { bg: "bg-cyan-100", text: "text-cyan-700", label: "Antar" },
    gojek: { bg: "bg-green-100", text: "text-green-700", label: "Gojek" },
    grab: { bg: "bg-emerald-100", text: "text-emerald-700", label: "Grab" },
    paxel: { bg: "bg-purple-100", text: "text-purple-700", label: "Paxel" },
    ninja: { bg: "bg-pink-100", text: "text-pink-700", label: "Ninja" },
    pos: { bg: "bg-amber-100", text: "text-amber-700", label: "Pos" },
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
