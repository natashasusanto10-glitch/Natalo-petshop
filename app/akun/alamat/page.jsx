import Link from "next/link";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import DeleteAlamatButton from "@/components/DeleteAlamatButton";

export default async function AddressListPage() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") redirect("/member/login");

  const addresses = await prisma.address.findMany({
    where: { userId: session.sub },
    orderBy: [{ isMain: "desc" }, { createdAt: "asc" }],
  });

  return (
    <main className="min-h-screen bg-zinc-50 px-4 py-8">
      <div className="mx-auto max-w-4xl">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <Link href="/member" className="text-sm font-bold text-natalo-700 hover:text-natalo-800">
              Kembali ke akun
            </Link>
            <h1 className="mt-2 text-3xl font-black tracking-tight text-zinc-950">Alamat Pengiriman</h1>
            <p className="mt-1 text-sm text-zinc-500">
              Simpan maksimal 3 alamat. Kode pos dipakai otomatis untuk cek ongkir.
            </p>
          </div>
          <Link
            href="/akun/alamat/tambah"
            className="rounded-full bg-natalo-600 px-5 py-3 text-sm font-black text-white transition hover:bg-natalo-700"
          >
            Tambah alamat
          </Link>
        </div>

        <div className="mt-8 space-y-4">
          {addresses.length === 0 ? (
            <section className="rounded-3xl border border-dashed border-zinc-200 bg-white p-10 text-center">
              <p className="text-sm font-semibold text-zinc-500">Belum ada alamat tersimpan.</p>
              <Link
                href="/akun/alamat/tambah"
                className="mt-4 inline-flex rounded-full bg-natalo-600 px-5 py-3 text-sm font-black text-white"
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

function AddressCard({ address }) {
  return (
    <section className="rounded-3xl border border-zinc-100 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-black text-zinc-950">{address.label}</span>
            {address.isMain && (
              <span className="rounded-full bg-natalo-100 px-2.5 py-1 text-xs font-black text-natalo-700">
                Utama
              </span>
            )}
          </div>
          <p className="mt-2 text-sm font-bold text-zinc-800">
            {address.recipient} · {address.phone}
          </p>
          <p className="mt-1 text-sm leading-6 text-zinc-600">{address.address}</p>
          <p className="mt-1 text-sm text-zinc-500">
            {[address.city].filter(Boolean).join(", ")}
            {address.postalCode ? ` ${address.postalCode}` : ""}
          </p>
          {address.pinpointAddress && (
            <p className="mt-1 text-xs text-zinc-400">📍 {address.pinpointAddress}</p>
          )}
        </div>
        <div className="flex shrink-0 flex-wrap gap-2">
          <Link
            href={`/akun/alamat/edit/${address.id}`}
            className="rounded-full border border-zinc-200 px-4 py-2 text-xs font-black text-zinc-700 transition hover:border-zinc-400"
          >
            Edit
          </Link>
          <DeleteAlamatButton id={address.id} />
        </div>
      </div>
    </section>
  );
}
