import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";

export default async function AdminVoucherEditPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const { id } = await params;
  const { error } = await searchParams;

  const voucher = await prisma.voucher.findUnique({ where: { id } });
  if (!voucher) return notFound();

  async function updateVoucher(formData: FormData) {
    "use server";

    const code = String(formData.get("code") || "").trim().toUpperCase();
    const description =
      String(formData.get("description") || "").trim() || null;
    const discountPercent = formData.get("discountPercent")
      ? parseInt(String(formData.get("discountPercent")), 10)
      : null;
    const discountAmount = formData.get("discountAmount")
      ? parseInt(String(formData.get("discountAmount")), 10)
      : null;
    const minimumOrder = parseInt(
      String(formData.get("minimumOrder") || "0"),
      10
    );
    const maxUsageRaw = String(formData.get("maxUsage") || "").trim();
    const maxUsage = maxUsageRaw ? parseInt(maxUsageRaw, 10) : null;
    const expiresAtRaw = String(formData.get("expiresAt") || "").trim();
    const expiresAt = expiresAtRaw ? new Date(expiresAtRaw) : null;
    const sourceTypeRaw = String(formData.get("sourceType") || "CUSTOMER").trim();
    const sourceType =
      sourceTypeRaw === "SELLER_MANUAL" ? "SELLER_MANUAL" : "CUSTOMER";

    if (!code) return;
    if (!discountPercent && !discountAmount) return;

    // Cek konflik kode (kalau diganti ke kode yang sudah dipakai voucher lain)
    if (code !== voucher!.code) {
      const existing = await prisma.voucher.findUnique({ where: { code } });
      if (existing && existing.id !== voucher!.id) {
        redirect(`/admin/vouchers/${id}/edit?error=exists`);
      }
    }

    // Validasi maxUsage tidak boleh lebih kecil dari usedCount
    if (maxUsage !== null && maxUsage < voucher!.usedCount) {
      redirect(`/admin/vouchers/${id}/edit?error=maxusage`);
    }

    await prisma.voucher.update({
      where: { id },
      data: {
        code,
        description,
        discountPercent,
        discountAmount,
        minimumOrder,
        maxUsage,
        expiresAt,
        sourceType,
      },
    });

    redirect("/admin/vouchers");
  }

  // Format expiresAt untuk input type="date" (YYYY-MM-DD)
  const expiresAtValue = voucher.expiresAt
    ? voucher.expiresAt.toISOString().slice(0, 10)
    : "";

  return (
    <div className="mx-auto max-w-2xl px-4 py-5 md:py-10">
      <Link
        href="/admin/vouchers"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke voucher
      </Link>
      <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
        Edit Voucher
      </h1>
      <p className="mt-1 text-sm text-zinc-500">
        Sudah dipakai{" "}
        <strong className="text-zinc-700">{voucher.usedCount}</strong> kali
        {voucher.maxUsage !== null && ` dari ${voucher.maxUsage}`}.
      </p>

      {error === "exists" && (
        <div className="mt-4 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-600">
          Kode voucher tersebut sudah dipakai voucher lain.
        </div>
      )}
      {error === "maxusage" && (
        <div className="mt-4 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-600">
          Maksimal penggunaan tidak boleh lebih kecil dari jumlah yang sudah
          terpakai ({voucher.usedCount}).
        </div>
      )}

      <form action={updateVoucher} className="mt-5 space-y-5 md:mt-8">
        <Field
          label="Kode voucher"
          name="code"
          required
          defaultValue={voucher.code}
          hint="Otomatis diubah ke huruf kapital. Hati-hati: mengubah kode akan invalidate kode lama."
        />
        <Field
          label="Deskripsi (opsional)"
          name="description"
          defaultValue={voucher.description ?? ""}
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Diskon persen (%)"
            name="discountPercent"
            type="number"
            defaultValue={voucher.discountPercent?.toString() ?? ""}
            hint="Isi salah satu atau keduanya"
          />
          <Field
            label="Diskon nominal (Rp)"
            name="discountAmount"
            type="number"
            defaultValue={voucher.discountAmount?.toString() ?? ""}
          />
        </div>

        <Field
          label="Minimum belanja (Rp)"
          name="minimumOrder"
          type="number"
          defaultValue={voucher.minimumOrder.toString()}
          placeholder="0 = tidak ada minimum"
        />

        <div>
          <label className="block text-sm font-medium text-zinc-700">Tipe voucher</label>
          <select
            name="sourceType"
            defaultValue={voucher.sourceType}
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
            defaultValue={voucher.maxUsage?.toString() ?? ""}
            placeholder="Kosong = tidak terbatas"
            hint={
              voucher.usedCount > 0
                ? `Tidak boleh < ${voucher.usedCount} (sudah terpakai)`
                : undefined
            }
          />
          <Field
            label="Berlaku hingga"
            name="expiresAt"
            type="date"
            defaultValue={expiresAtValue}
            hint="Kosong = tidak ada batas waktu"
          />
        </div>

        <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row">
          <Link
            href="/admin/vouchers"
            className="rounded-full border border-zinc-300 px-6 py-3 text-center text-sm font-bold hover:bg-zinc-50"
          >
            Batal
          </Link>
          <button
            type="submit"
            className="flex-1 rounded-full bg-zinc-950 px-6 py-3 text-sm font-bold text-white hover:bg-zinc-800 sm:flex-none"
          >
            Simpan perubahan
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
