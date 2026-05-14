import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import FormAlamat from "@/components/FormAlamat";
import { StickyBackTitle } from "@/components/StickyBackTitle";

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
    <main className="min-h-screen bg-slate-50 pb-[calc(96px+env(safe-area-inset-bottom))]">
      <StickyBackTitle label={backLabel} href={returnUrl} variant="textBack" stickToTop />
      <div className="mx-auto max-w-md px-4 py-6 sm:py-8">
        <section className="rounded-3xl border border-slate-100 bg-white p-4 shadow-sm sm:p-6">
          <h1 className="text-2xl font-black tracking-tight text-slate-950">Tambah Alamat</h1>
          <p className="mt-1 text-sm font-semibold leading-6 text-slate-500">
            Lengkapi alamat, label, wilayah, dan titik peta pengiriman.
          </p>
          <div className="mt-6">
            <FormAlamat mode="create" />
          </div>
        </section>
      </div>
    </main>
  );
}
