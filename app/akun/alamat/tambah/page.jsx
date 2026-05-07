import Link from "next/link";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import FormAlamat from "@/components/FormAlamat";

export default async function AddAddressPage() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") redirect("/member/login");

  return (
    <main className="min-h-screen bg-zinc-50 px-4 py-8">
      <div className="mx-auto max-w-3xl">
        <Link href="/akun/alamat" className="text-sm font-bold text-natalo-700 hover:text-natalo-800">
          Kembali ke alamat
        </Link>
        <section className="mt-5 rounded-3xl border border-zinc-100 bg-white p-6 shadow-sm">
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
