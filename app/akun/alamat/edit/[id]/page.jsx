import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import FormAlamat from "@/components/FormAlamat";

export default async function EditAddressPage({ params, searchParams }) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") redirect("/member/login");

  const { id } = await params;
  const sp = (await searchParams) ?? {};
  const rawReturn = typeof sp.return === "string" ? sp.return : "";
  const returnUrl =
    rawReturn.startsWith("/") && !rawReturn.startsWith("//") ? rawReturn : "/akun/alamat";
  const source = sp.source === "checkout" ? "checkout" : "profile";
  const backLabel = source === "checkout" ? "Kembali pilih alamat" : "Kembali ke alamat";

  const address = await prisma.address.findFirst({
    where: { id, userId: session.sub },
  });

  if (!address) notFound();

  return (
    <main className="min-h-screen bg-slate-50 px-4 py-6 pb-24 sm:py-8">
      <div className="mx-auto max-w-md">
        <Link href={returnUrl} className="text-sm font-bold text-natalo-700 hover:text-natalo-800">
          {backLabel}
        </Link>
        <section className="mt-5 rounded-3xl border border-slate-100 bg-white p-4 shadow-sm sm:p-6">
          <h1 className="text-2xl font-black tracking-tight text-slate-950">Edit Alamat</h1>
          <p className="mt-1 text-sm font-semibold leading-6 text-slate-500">
            Perbarui alamat, label, wilayah, dan titik peta pengiriman.
          </p>
          <div className="mt-6">
            <FormAlamat mode="edit" initialAddress={JSON.parse(JSON.stringify(address))} />
          </div>
        </section>
      </div>
    </main>
  );
}
