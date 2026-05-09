import Link from "next/link";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import FormAlamat from "@/components/FormAlamat";

function safeInternalPath(value, fallback) {
  return typeof value === "string" && value.startsWith("/") && !value.startsWith("//")
    ? value
    : fallback;
}

export default async function AddAddressPage({ searchParams }) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") redirect("/member/login");

  const sp = (await searchParams) ?? {};
  const returnUrl = safeInternalPath(sp.return, "/akun/alamat");
  const source = sp.source === "checkout" ? "checkout" : "profile";
  const backLabel = source === "checkout" ? "Kembali pilih alamat" : "Kembali ke alamat";

  return (
    <main className="min-h-screen bg-zinc-50 px-4 py-6 pb-24 sm:py-8">
      <div className="mx-auto max-w-xl">
        <Link href={returnUrl} className="text-sm font-bold text-natalo-700 hover:text-natalo-800">
          {backLabel}
        </Link>
        <section className="mt-5 rounded-3xl border border-zinc-100 bg-white p-4 shadow-sm sm:p-6">
          <h1 className="text-2xl font-black tracking-tight text-zinc-950">Tambah Alamat</h1>
          <p className="mt-1 text-sm text-zinc-500">
            Pilih wilayah bertingkat agar kode pos otomatis terisi untuk ongkir.
          </p>
          <div className="mt-6">
            <FormAlamat mode="create" />
          </div>
        </section>
      </div>
    </main>
  );
}
