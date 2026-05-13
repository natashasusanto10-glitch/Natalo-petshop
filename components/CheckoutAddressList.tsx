"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  FiArrowLeft,
  FiCheck,
  FiEdit3,
  FiMapPin,
  FiPlus,
} from "react-icons/fi";

const CHECKOUT_SELECTED_ADDRESS_KEY = "checkout:selectedAddressId";
const CHECKOUT_DRAFT_KEY = "checkout:draft";
const CHECKOUT_ADDRESS_FORCE_APPLY_KEY = "checkout:addressForceApply";

type CheckoutAddress = {
  id: string;
  label: string | null;
  recipient: string;
  phone: string;
  address: string;
  city: string | null;
  postalCode: string | null;
  areaId: string | null;
  areaLabel: string | null;
  provinceName: string | null;
  cityName: string | null;
  districtName: string | null;
  isMain: boolean;
  latitude: number | null;
  longitude: number | null;
  pinpointAddress: string | null;
  streetName: string | null;
};

type Props = {
  addresses: CheckoutAddress[];
  returnTo: string;
};

function encodePath(path: string) {
  return encodeURIComponent(path);
}

function hasUsablePinpoint(latitude?: number | null, longitude?: number | null) {
  return (
    typeof latitude === "number" &&
    Number.isFinite(latitude) &&
    typeof longitude === "number" &&
    Number.isFinite(longitude) &&
    !(latitude === 0 && longitude === 0)
  );
}

function Badge({
  children,
  tone = "blue",
}: {
  children: React.ReactNode;
  tone?: "blue" | "dark" | "green" | "amber" | "red" | "slate";
}) {
  const styles = {
    blue: "border-natalo-100 bg-natalo-50 text-natalo-700",
    dark: "border-slate-900 bg-slate-950 text-white",
    green: "border-emerald-100 bg-emerald-50 text-emerald-700",
    amber: "border-amber-100 bg-amber-50 text-amber-700",
    red: "border-red-100 bg-red-50 text-red-700",
    slate: "border-slate-200 bg-slate-50 text-slate-600",
  };

  return (
    <span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-[11px] font-black ${styles[tone]}`}>
      {children}
    </span>
  );
}

function AddressRegion({ address }: { address: CheckoutAddress }) {
  const region = [
    address.districtName,
    address.cityName || address.city,
    address.provinceName,
  ]
    .filter(Boolean)
    .join(", ");
  const legacyRegion = [address.areaLabel || address.city].filter(Boolean).join(", ");
  const displayRegion = region || legacyRegion;

  if (!displayRegion && !address.postalCode) return null;

  return (
    <p className="text-sm font-semibold leading-6 text-slate-500">
      {displayRegion}
      {address.postalCode ? ` ${address.postalCode}` : ""}
    </p>
  );
}

export function CheckoutAddressList({ addresses, returnTo }: Props) {
  const router = useRouter();
  const [selectedId, setSelectedId] = useState("");
  const encodedReturnTo = useMemo(() => encodePath(returnTo), [returnTo]);
  const listReturn = `/checkout/addresses?returnTo=${encodedReturnTo}`;
  const encodedListReturn = useMemo(() => encodePath(listReturn), [listReturn]);
  const addAddressHref = `/akun/alamat/tambah?source=checkout&return=${encodedListReturn}&checkoutReturn=${encodedReturnTo}`;

  useEffect(() => {
    let draftSelectedId = "";
    try {
      const draft = JSON.parse(sessionStorage.getItem(CHECKOUT_DRAFT_KEY) || "null");
      draftSelectedId = draft?.selectedAddressId || "";
    } catch {
      draftSelectedId = "";
    }
    setSelectedId(
      sessionStorage.getItem(CHECKOUT_SELECTED_ADDRESS_KEY) ||
        draftSelectedId ||
        addresses[0]?.id ||
        "",
    );
  }, [addresses]);

  function chooseAddress(id: string) {
    setSelectedId(id);
  }

  function confirmSelection() {
    if (!selectedId) return;
    let draftSelectedId = "";
    try {
      const draft = JSON.parse(sessionStorage.getItem(CHECKOUT_DRAFT_KEY) || "null");
      draftSelectedId = draft?.selectedAddressId || "";
    } catch {
      draftSelectedId = "";
    }
    sessionStorage.setItem(CHECKOUT_SELECTED_ADDRESS_KEY, selectedId);
    if (selectedId !== draftSelectedId) {
      sessionStorage.setItem(CHECKOUT_ADDRESS_FORCE_APPLY_KEY, "1");
    }
    router.push(returnTo);
  }

  return (
    <main className="min-h-screen bg-slate-50 pb-[calc(104px+env(safe-area-inset-bottom))]">
      <div className="sticky top-[calc(var(--natalo-mobile-header-min-height)+env(safe-area-inset-top))] z-[900] border-b border-slate-100 bg-white/95 backdrop-blur">
        <div className="mx-auto flex max-w-2xl items-center justify-between gap-3 px-4 py-3">
          <Link
            href={returnTo}
            className="inline-flex min-w-0 items-center gap-2 py-2 text-sm font-black text-slate-800 transition hover:text-natalo-700 active:opacity-70"
          >
            <FiArrowLeft className="h-4 w-4 shrink-0" aria-hidden="true" />
            <span className="truncate">Kembali ke checkout</span>
          </Link>
          <Link
            href={addAddressHref}
            className="inline-flex shrink-0 items-center gap-1.5 py-2 text-sm font-black text-natalo-700 transition hover:text-natalo-800 active:opacity-70"
          >
            <FiPlus className="h-4 w-4" aria-hidden="true" />
            Tambah
          </Link>
        </div>
      </div>

      <div className="mx-auto max-w-2xl px-4 pt-7">
        <section>
          <h1 className="text-[28px] font-black leading-tight tracking-tight text-slate-950">
            Pilih Alamat Pengiriman
          </h1>
          <p className="mt-2 max-w-md text-sm font-semibold leading-6 text-slate-500">
            Pilihan ini hanya dipakai untuk pesanan checkout saat ini.
          </p>
        </section>

        <div className="mt-7 space-y-4">
          {addresses.length === 0 ? (
            <section className="rounded-[28px] border border-dashed border-natalo-200 bg-white p-8 text-center shadow-sm">
              <div className="mx-auto grid h-14 w-14 place-items-center rounded-3xl bg-natalo-50 text-natalo-700">
                <FiMapPin className="h-6 w-6" aria-hidden="true" />
              </div>
              <p className="mt-4 text-base font-black text-slate-900">Belum ada alamat tersimpan.</p>
              <p className="mt-1 text-sm font-semibold leading-6 text-slate-500">
                Tambahkan alamat pertama untuk melanjutkan checkout.
              </p>
              <Link
                href={addAddressHref}
                className="mt-5 inline-flex h-12 items-center justify-center rounded-2xl bg-natalo-600 px-5 text-sm font-black text-white shadow-sm"
              >
                Tambah alamat pertama
              </Link>
            </section>
          ) : (
            addresses.map((address) => {
              const selected = selectedId === address.id;
              const hasPinpoint = hasUsablePinpoint(address.latitude, address.longitude);
              const hasArea = Boolean(
                address.areaId ||
                  (address.provinceName &&
                    address.cityName &&
                    address.districtName &&
                    address.postalCode),
              );
              const editHref = `/akun/alamat/edit/${address.id}?source=checkout&return=${encodedListReturn}&checkoutReturn=${encodedReturnTo}`;

              return (
                <section
                  key={address.id}
                  className={`rounded-[28px] border bg-white p-5 shadow-[0_14px_34px_rgba(15,23,42,0.06)] transition ${
                    selected
                      ? "border-natalo-300 ring-4 ring-natalo-100"
                      : "border-natalo-100 hover:border-natalo-200"
                  }`}
                >
                  <button
                    type="button"
                    onClick={() => chooseAddress(address.id)}
                    className="block w-full rounded-[22px] text-left outline-none focus-visible:ring-4 focus-visible:ring-natalo-100"
                  >
                    <div className="flex items-start gap-4">
                      <span
                        aria-hidden="true"
                        className={`mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-full border transition ${
                          selected
                            ? "border-natalo-600 bg-natalo-600 text-white"
                            : "border-slate-300 bg-white text-transparent"
                        }`}
                      >
                        <FiCheck className="h-4 w-4" />
                      </span>

                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          {address.label && <Badge>{address.label}</Badge>}
                          {address.isMain && <Badge>Utama</Badge>}
                          {selected && <Badge tone="dark">Dipilih</Badge>}
                          <Badge tone={hasPinpoint ? "green" : "amber"}>
                            {hasPinpoint ? "Pinpoint OK" : "Perlu pinpoint"}
                          </Badge>
                          <Badge tone={hasArea ? "green" : "red"}>
                            {hasArea ? "Area Biteship OK" : "Perlu pilih area"}
                          </Badge>
                        </div>

                        <div className="mt-4 space-y-2">
                          <div>
                            <p className="text-base font-black leading-tight text-slate-950">
                              {address.recipient}
                            </p>
                            <p className="mt-1 text-sm font-bold text-slate-600">{address.phone}</p>
                          </div>

                          <div className="rounded-3xl bg-slate-50 px-4 py-3">
                            <p className="text-sm font-bold leading-6 text-slate-800">
                              {address.address}
                            </p>
                            <AddressRegion address={address} />
                          </div>

                          {address.streetName && (
                            <div className="rounded-2xl border border-natalo-100 bg-white px-4 py-3">
                              <p className="text-[11px] font-black uppercase tracking-wide text-natalo-700">
                                Nama toko / patokan
                              </p>
                              <p className="mt-1 text-sm font-bold leading-6 text-slate-800">
                                {address.streetName}
                              </p>
                            </div>
                          )}

                          {hasPinpoint && address.pinpointAddress && (
                            <div className="flex gap-3 rounded-2xl bg-natalo-50 px-4 py-3 text-natalo-900">
                              <FiMapPin className="mt-0.5 h-4 w-4 shrink-0 text-natalo-700" aria-hidden="true" />
                              <p className="text-xs font-semibold leading-5">
                                {address.pinpointAddress}
                              </p>
                            </div>
                          )}

                          {!hasPinpoint && (
                            <p className="rounded-2xl bg-amber-50 px-4 py-3 text-xs font-bold leading-5 text-amber-700">
                              Tambahkan pinpoint agar pengiriman lebih akurat.
                            </p>
                          )}
                          {!hasArea && (
                            <p className="rounded-2xl bg-red-50 px-4 py-3 text-xs font-bold leading-5 text-red-700">
                              Alamat lama perlu diperbarui. Pilih kota/kecamatan dari daftar Biteship agar ongkir valid.
                            </p>
                          )}
                        </div>
                      </div>
                    </div>
                  </button>

                  <div className="mt-5 flex justify-end border-t border-slate-100 pt-4">
                    <Link
                      href={editHref}
                      className="inline-flex h-10 items-center gap-2 rounded-2xl border border-slate-200 bg-white px-4 text-xs font-black text-slate-700 transition hover:border-natalo-300 hover:text-natalo-700"
                    >
                      <FiEdit3 className="h-3.5 w-3.5" aria-hidden="true" />
                      Edit
                    </Link>
                  </div>
                </section>
              );
            })
          )}
        </div>
      </div>

      <div className="fixed inset-x-0 bottom-0 z-[950] border-t border-slate-200 bg-white/95 px-4 py-3 shadow-[0_-10px_30px_rgba(15,23,42,0.10)] backdrop-blur [padding-bottom:calc(12px+env(safe-area-inset-bottom))]">
        <div className="mx-auto grid max-w-2xl grid-cols-[minmax(92px,0.7fr)_minmax(0,1.3fr)] items-center gap-3">
          <button
            type="button"
            onClick={() => router.push(returnTo)}
            className="h-12 rounded-2xl border border-slate-200 bg-white px-4 text-sm font-black text-slate-700 transition hover:bg-slate-50 active:scale-[0.98]"
          >
            Batal
          </button>
          <button
            type="button"
            onClick={confirmSelection}
            disabled={!selectedId}
            className="h-12 rounded-2xl bg-natalo-600 px-5 text-sm font-black text-white shadow-sm transition hover:bg-natalo-700 active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-500"
          >
            Pilih Alamat
          </button>
        </div>
      </div>
    </main>
  );
}
