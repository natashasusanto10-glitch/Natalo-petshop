import Link from "next/link";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";

export default async function AdminVoucherNewPage() {
  async function createVoucher(formData: FormData) {
    "use server";

    const code = String(formData.get("code") || "").trim().toUpperCase();
    const description = String(formData.get("description") || "").trim() || null;
    const discountPercent = formData.get("discountPercent")
      ? parseInt(String(formData.get("discountPercent")), 10)
      : null;
    const discountAmount = formData.get("discountAmount")
      ? parseInt(String(formData.get("discountAmount")), 10)
      : null;
    const minimumOrder = parseInt(String(formData.get("minimumOrder") || "0"), 10);
    const maxUsageRaw = String(formData.get("maxUsage") || "").trim();
    const maxUsage = maxUsageRaw ? parseInt(maxUsageRaw, 10) : null;
    const expiresAtRaw = String(formData.get("expiresAt") || "").trim();
    const expiresAt = expiresAtRaw ? new Date(expiresAtRaw) : null;
    const sourceTypeRaw = String(formData.get("sourceType") || "CUSTOMER").trim();
    const sourceType =
      sourceTypeRaw === "SELLER_MANUAL" ? "SELLER_MANUAL" : "CUSTOMER";

    if (!code) return;
    if (!discountPercent && !discountAmount) return;

    const existing = await prisma.voucher.findUnique({ where: { code } });
    if (existing) redirect("/admin/vouchers/new?error=exists");

    await prisma.voucher.create({
      data: {
        code,
        description,
        discountPercent,
        discountAmount,
        minimumOrder,
        maxUsage,
        expiresAt,
        isActive: true,
        sourceType,
      },
    });

    redirect("/admin/vouchers");
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-5 md:py-10">
      <Link href="/admin/vouchers" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
        ← Kembali ke voucher
      </Link>
      <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">Buat Voucher</h1>

      <form action={createVoucher} className="mt-5 space-y-5 md:mt-8">
        <Field
          label="Kode voucher"
          name="code"
          required
          placeholder="Contoh: LEBARAN20"
          hint="Otomatis diubah ke huruf kapital"
        />
        <Field
          label="Deskripsi (opsional)"
          name="description"
          placeholder="Contoh: Promo Lebaran 2025"
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Diskon persen (%)"
            name="discountPercent"
            type="number"
            placeholder="Contoh: 10 untuk 10%"
            hint="Isi salah satu atau keduanya"
          />
          <Field
            label="Diskon nominal (Rp)"
            name="discountAmount"
            type="number"
            placeholder="Contoh: 15000"
          />
        </div>

        <Field
          label="Minimum belanja (Rp)"
          name="minimumOrder"
          type="number"
          placeholder="0 = tidak ada minimum"
          defaultValue="0"
        />

        <div>
          <label className="block text-sm font-medium text-zinc-700">Tipe voucher</label>
          <select
            name="sourceType"
            defaultValue="CUSTOMER"
            className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
          >
            <option value="CUSTOMER">Voucher Pembeli (publik / claim user)</option>
            <option value="SELLER_MANUAL">Voucher Manual Penjual (rahasia)</option>
          </select>
          <p className="mt-1 text-xs text-zinc-400">
            <strong>Pembeli</strong>: muncul di daftar voucher checkout, bisa
            di-pilih atau auto-apply. <strong>Manual penjual</strong>:
            tersembunyi, hanya bisa dipakai jika pembeli memasukkan kode
            secara manual. 1 checkout maks 1 dari masing-masing tipe.
          </p>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Maks. penggunaan"
            name="maxUsage"
            type="number"
            placeholder="Kosong = tidak terbatas"
          />
          <Field
            label="Berlaku hingga"
            name="expiresAt"
            type="date"
            placeholder=""
            hint="Kosong = tidak ada batas waktu"
          />
        </div>

        <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row">
          <Link
            href="/admin/vouchers"
            className="rounded-full border border-zinc-300 px-6 py-3 text-center text-sm font-bold"
          >
            Batal
          </Link>
          <button
            type="submit"
            className="flex-1 rounded-full bg-zinc-950 px-6 py-3 text-sm font-bold text-white sm:flex-none"
          >
            Buat voucher
          </button>
        </div>
      </form>
    </div>
  );
}

function Field({
  label,
  name,
  type = "text",
  required,
  placeholder,
  hint,
  defaultValue,
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
  placeholder?: string;
  hint?: string;
  defaultValue?: string;
}) {
  return (
    <div>
      <label className="block text-sm font-medium text-zinc-700">
        {label}
        {required && <span className="ml-1 text-red-500">*</span>}
      </label>
      <input
        type={type}
        name={name}
        required={required}
        placeholder={placeholder}
        defaultValue={defaultValue}
        min={type === "number" ? 0 : undefined}
        className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
      />
      {hint && <p className="mt-1 text-xs text-zinc-400">{hint}</p>}
    </div>
  );
}
