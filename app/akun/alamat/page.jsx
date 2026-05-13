import Link from "next/link";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import DeleteAlamatButton from "@/components/DeleteAlamatButton";
import SetPrimaryAddressButton from "@/components/SetPrimaryAddressButton";
import { StickyBackTitle } from "@/components/StickyBackTitle";

export default async function AddressListPage() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") redirect("/member/login");

  const addresses = await prisma.address.findMany({
    where: { userId: session.sub },
    orderBy: [{ isMain: "desc" }, { createdAt: "asc" }],
  });

  return (
    <main className="min-h-screen bg-slate-50 pb-24">
      <StickyBackTitle label="Kembali ke akun" href="/member" variant="textBack" />
      <div className="mx-auto max-w-md px-4 py-6 sm:py-8">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-2xl font-black tracking-tight text-slate-950">Daftar Alamat</h1>
            <p className="mt-1 text-sm font-semibold leading-6 text-slate-500">
              Kelola alamat pengiriman Natalo Petshop.
            </p>
          </div>
          <Link
            href="/akun/alamat/tambah"
            className="shrink-0 rounded-2xl bg-natalo-600 px-4 py-3 text-xs font-black text-white shadow-sm transition hover:bg-natalo-700"
          >
            Tambah
          </Link>
        </div>

        <div className="mt-6 space-y-3">
          {addresses.length === 0 ? (
            <section className="rounded-3xl border border-dashed border-slate-200 bg-white p-8 text-center shadow-sm">
              <p className="text-sm font-black text-slate-700">Belum ada alamat tersimpan.</p>
              <p className="mt-1 text-xs font-semibold text-slate-500">
                Tambahkan alamat pertama untuk checkout lebih cepat.
              </p>
              <Link
                href="/akun/alamat/tambah"
                className="mt-4 inline-flex rounded-2xl bg-natalo-600 px-5 py-3 text-sm font-black text-white"
              >
                Tambah alamat pertama
              </Link>
            </section>
          ) : (
            addresses.map((address) => <AddressCard key={address.id} address={address} />)
          )}
        </div>
      </div>
    </main>
  );
}

function hasUsablePinpoint(latitude, longitude) {
  return (
    typeof latitude === "number" &&
    Number.isFinite(latitude) &&
    typeof longitude === "number" &&
    Number.isFinite(longitude) &&
    !(latitude === 0 && longitude === 0)
  );
}

function AddressCard({ address }) {
  const hasPinpoint = hasUsablePinpoint(address.latitude, address.longitude);
  const hasArea = Boolean(
    address.areaId ||
      (address.provinceName && address.cityName && address.districtName && address.postalCode)
  );

  return (
    <section className="rounded-3xl border border-slate-100 bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            {address.label && (
              <span className="rounded-full border border-natalo-200 bg-white px-2.5 py-1 text-xs font-black text-natalo-700">
                {address.label}
              </span>
            )}
            {address.isMain && (
              <span className="rounded-full bg-natalo-600 px-2.5 py-1 text-xs font-black text-white">
                Utama
              </span>
            )}
            <span
              className={`rounded-full px-2.5 py-1 text-xs font-black ${
                hasPinpoint ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-700"
              }`}
            >
              {hasPinpoint ? "Pinpoint OK" : "Perlu pinpoint"}
            </span>
            <span
              className={`rounded-full px-2.5 py-1 text-xs font-black ${
                hasArea ? "bg-emerald-50 text-emerald-700" : "bg-red-50 text-red-700"
              }`}
            >
              {hasArea ? "Area Biteship OK" : "Perlu pilih area"}
            </span>
          </div>
          <p className="mt-3 text-sm font-black text-slate-950">
            {address.recipient} - {address.phone}
          </p>
          <p className="mt-1 text-sm font-semibold leading-6 text-slate-600">{address.address}</p>
          {address.streetName && (
            <p className="mt-1 text-xs font-semibold leading-5 text-slate-500">{address.streetName}</p>
          )}
          <p className="mt-2 text-sm font-semibold text-slate-500">
            {[address.districtName, address.cityName || address.city, address.provinceName].filter(Boolean).join(", ")}
            {address.postalCode ? ` ${address.postalCode}` : ""}
          </p>
          {hasPinpoint && address.pinpointAddress && (
            <p className="mt-2 rounded-2xl bg-natalo-50 px-3 py-2 text-xs font-semibold leading-5 text-natalo-800">
              Pinpoint: {address.pinpointAddress}
            </p>
          )}
          {!hasPinpoint && (
            <p className="mt-2 rounded-2xl bg-amber-50 px-3 py-2 text-xs font-semibold leading-5 text-amber-700">
              Tambahkan pinpoint supaya alamat lebih akurat saat checkout.
            </p>
          )}
          {!hasArea && (
            <p className="mt-2 rounded-2xl bg-slate-50 px-3 py-2 text-xs font-semibold leading-5 text-slate-600">
              Wilayah manual tersimpan. Ongkir checkout tetap akan memakai data wilayah yang tersedia.
            </p>
          )}
        </div>
      </div>
      <div className="mt-4 flex flex-wrap justify-end gap-2 border-t border-slate-100 pt-4">
        {!address.isMain && <SetPrimaryAddressButton id={address.id} disabled={false} />}
        <Link
          href={`/akun/alamat/edit/${address.id}`}
          className="rounded-full border border-slate-200 px-4 py-2 text-xs font-black text-slate-700 transition hover:border-natalo-300 hover:text-natalo-700"
        >
          Edit
        </Link>
        <DeleteAlamatButton id={address.id} />
      </div>
    </section>
  );
}
