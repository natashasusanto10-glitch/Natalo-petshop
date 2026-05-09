"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";

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
  isMain: boolean;
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

export function CheckoutAddressList({ addresses, returnTo }: Props) {
  const router = useRouter();
  const [selectedId, setSelectedId] = useState("");
  const encodedReturnTo = useMemo(() => encodePath(returnTo), [returnTo]);
  const listReturn = `/checkout/addresses?returnTo=${encodedReturnTo}`;
  const encodedListReturn = useMemo(() => encodePath(listReturn), [listReturn]);

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
    <main className="min-h-screen bg-zinc-50 px-4 py-6 pb-28">
      <div className="mx-auto max-w-2xl">
        <div className="flex items-start justify-between gap-4">
          <div>
            <Link href={returnTo} className="text-sm font-bold text-natalo-700 hover:text-natalo-800">
              Kembali ke checkout
            </Link>
            <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950">
              Pilih Alamat Pengiriman
            </h1>
            <p className="mt-1 text-sm text-zinc-500">
              Pilihan ini hanya dipakai untuk pesanan checkout saat ini.
            </p>
          </div>
          <Link
            href={`/akun/alamat/tambah?source=checkout&return=${encodedListReturn}&checkoutReturn=${encodedReturnTo}`}
            className="shrink-0 rounded-full bg-natalo-600 px-4 py-2.5 text-xs font-black text-white transition hover:bg-natalo-700"
          >
            Tambah
          </Link>
        </div>

        <div className="mt-6 space-y-3">
          {addresses.length === 0 ? (
            <section className="rounded-3xl border border-dashed border-zinc-200 bg-white p-8 text-center">
              <p className="text-sm font-semibold text-zinc-500">Belum ada alamat tersimpan.</p>
              <Link
                href={`/akun/alamat/tambah?source=checkout&return=${encodedListReturn}&checkoutReturn=${encodedReturnTo}`}
                className="mt-4 inline-flex rounded-full bg-natalo-600 px-5 py-3 text-sm font-black text-white"
              >
                Tambah alamat pertama
              </Link>
            </section>
          ) : (
            addresses.map((address) => {
              const selected = selectedId === address.id;
              return (
                <section
                  key={address.id}
                  className={`rounded-3xl border bg-white p-4 shadow-sm transition ${
                    selected ? "border-natalo-500 ring-4 ring-natalo-100" : "border-zinc-100"
                  }`}
                >
                  <button
                    type="button"
                    onClick={() => chooseAddress(address.id)}
                    className="block w-full text-left"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-black text-zinc-950">{address.label || "Alamat"}</span>
                          {address.isMain && (
                            <span className="rounded-full bg-natalo-100 px-2.5 py-1 text-xs font-black text-natalo-700">
                              Utama
                            </span>
                          )}
                          {selected && (
                            <span className="rounded-full bg-zinc-950 px-2.5 py-1 text-xs font-black text-white">
                              Dipilih
                            </span>
                          )}
                        </div>
                        <p className="mt-2 text-sm font-bold text-zinc-800">
                          {address.recipient} - {address.phone}
                        </p>
                        <p className="mt-1 text-sm leading-6 text-zinc-600">{address.address}</p>
                        <p className="mt-1 text-sm text-zinc-500">
                          {[address.city].filter(Boolean).join(", ")}
                          {address.postalCode ? ` ${address.postalCode}` : ""}
                        </p>
                        {address.streetName && (
                          <p className="mt-2 text-xs font-bold text-natalo-700">{address.streetName}</p>
                        )}
                        {address.pinpointAddress && (
                          <p className="mt-2 rounded-2xl bg-natalo-50 px-3 py-2 text-xs font-semibold text-natalo-800">
                            Pinpoint: {address.pinpointAddress}
                          </p>
                        )}
                      </div>
                      <span
                        aria-hidden="true"
                        className={`mt-1 grid h-6 w-6 shrink-0 place-items-center rounded-full border ${
                          selected ? "border-natalo-600 bg-natalo-600 text-white" : "border-zinc-300"
                        }`}
                      >
                        {selected ? "OK" : ""}
                      </span>
                    </div>
                  </button>

                  <div className="mt-4 flex justify-end">
                    <Link
                      href={`/akun/alamat/edit/${address.id}?source=checkout&return=${encodedListReturn}&checkoutReturn=${encodedReturnTo}`}
                      className="rounded-full border border-zinc-200 px-4 py-2 text-xs font-black text-zinc-700 transition hover:border-natalo-300 hover:text-natalo-700"
                    >
                      Edit
                    </Link>
                  </div>
                </section>
              );
            })
          )}
        </div>
      </div>

      {addresses.length > 0 && (
        <div className="fixed inset-x-0 bottom-0 z-40 border-t border-zinc-200 bg-white px-4 py-3 shadow-[0_-4px_12px_rgba(0,0,0,0.06)] [padding-bottom:calc(12px+env(safe-area-inset-bottom))]">
          <div className="mx-auto flex max-w-2xl gap-2">
            <button
              type="button"
              onClick={() => router.push(returnTo)}
              className="h-12 rounded-full px-5 text-sm font-black text-zinc-600 transition hover:bg-zinc-50"
            >
              Batal
            </button>
            <button
              type="button"
              onClick={confirmSelection}
              disabled={!selectedId}
              className="h-12 flex-1 rounded-full bg-natalo-600 px-5 text-sm font-black text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
            >
              Pilih Alamat
            </button>
          </div>
        </div>
      )}
    </main>
  );
}
