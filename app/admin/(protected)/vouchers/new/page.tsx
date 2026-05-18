import Link from "next/link";
import { redirect } from "next/navigation";
import type { VoucherUserUsageLimitPeriod } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import {
  deriveVoucherSourceType,
  isAdminCreatableVoucherKind,
  voucherKindDescription,
} from "@/lib/voucher-kind";
import { VoucherTargetFields } from "@/components/admin/VoucherTargetFields";

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
    const maxDiscountRaw = String(formData.get("maxDiscountAmount") || "").trim();
    const maxDiscountAmount = maxDiscountRaw ? parseInt(maxDiscountRaw, 10) : null;
    const minimumOrder = parseInt(String(formData.get("minimumOrder") || "0"), 10);
    const maxUsageRaw = String(formData.get("maxUsage") || "").trim();
    const maxUsage = maxUsageRaw ? parseInt(maxUsageRaw, 10) : null;
    const startsAtRaw = String(formData.get("startsAt") || "").trim();
    const startsAt = startsAtRaw ? new Date(startsAtRaw) : new Date();
    const expiresAtRaw = String(formData.get("expiresAt") || "").trim();
    const expiresAt = expiresAtRaw ? new Date(expiresAtRaw) : null;
    const kindRaw = String(formData.get("kind") || "PRODUCT_DISCOUNT").trim();
    if (!isAdminCreatableVoucherKind(kindRaw)) return;
    const kind = kindRaw;
    const sourceType = deriveVoucherSourceType(kind);
    const newMemberRulesEnabled = formData.get("newMemberRulesEnabled") === "1";
    const targetUser =
      kind === "PRODUCT_DISCOUNT" &&
      newMemberRulesEnabled &&
      String(formData.get("targetUser") || "ALL_MEMBERS") === "NEW_MEMBER"
        ? "NEW_MEMBER"
        : "ALL_MEMBERS";
    const newMemberMaxAgeRaw = String(formData.get("newMemberMaxAccountAgeDays") || "").trim();
    const newMemberMaxAccountAgeDays =
      targetUser === "NEW_MEMBER" && newMemberMaxAgeRaw
        ? parseInt(newMemberMaxAgeRaw, 10)
        : null;
    const newMemberRequireNoSuccessfulOrder =
      targetUser === "NEW_MEMBER" &&
      formData.get("newMemberRequireNoSuccessfulOrder") === "on";
    const usageLimitPeriodRaw = String(formData.get("usageLimitPeriod") || "NONE").trim();
    const usageLimitPeriod =
      (kind === "PRODUCT_DISCOUNT" || kind === "FREE_SHIPPING") &&
      ["NONE", "LIFETIME", "DAY", "WEEK", "MONTH"].includes(usageLimitPeriodRaw)
        ? (usageLimitPeriodRaw as VoucherUserUsageLimitPeriod)
        : "LIFETIME";
    const usageLimitRaw = String(formData.get("usageLimitPerUser") || "1").trim();
    const usageLimitPerUser =
      usageLimitPeriod === "NONE"
        ? 0
        : usageLimitPeriod === "LIFETIME"
          ? 1
          : Math.max(1, parseInt(usageLimitRaw || "1", 10) || 1);
    const isActive = formData.get("isActive") === "on";

    if (!code) return;
    const isFreeShipping = kind === "FREE_SHIPPING";
    if (!isFreeShipping && !discountPercent && !discountAmount) return;

    const existing = await prisma.voucher.findUnique({ where: { code } });
    if (existing) redirect("/admin/vouchers/new?error=exists");

    await prisma.voucher.create({
      data: {
        code,
        description,
        discountPercent: isFreeShipping ? null : discountPercent,
        discountAmount: isFreeShipping ? null : discountAmount,
        maxDiscountAmount: isFreeShipping ? null : maxDiscountAmount,
        minimumOrder,
        maxUsage,
        startsAt,
        expiresAt,
        isActive,
        sourceType,
        kind,
        targetUser,
        newMemberMaxAccountAgeDays,
        newMemberRequireNoSuccessfulOrder,
        usageLimitPeriod,
        usageLimitPerUser,
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
          label="Maksimal diskon (Rp)"
          name="maxDiscountAmount"
          type="number"
          placeholder="Contoh: 25000"
          hint="Opsional. Dipakai untuk membatasi diskon persen."
        />

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
            name="kind"
            defaultValue="PRODUCT_DISCOUNT"
            className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
          >
            <option value="PRODUCT_DISCOUNT">Voucher Diskon Produk - Semua Member</option>
            <option value="FREE_SHIPPING">Voucher Gratis Ongkir - Semua Member</option>
            <option value="MANUAL_PRIVATE">Voucher Manual / Private</option>
          </select>
          <p className="mt-1 text-xs text-zinc-400">
            {voucherKindDescription("PRODUCT_DISCOUNT")} Gratis ongkir tidak
            perlu nominal diskon. Voucher hasil klaim loyalty point dibuat
            otomatis dari halaman user, bukan dari admin.
          </p>
        </div>

        <VoucherTargetFields />

        <div className="grid gap-4 sm:grid-cols-3">
          <Field
            label="Maks. penggunaan"
            name="maxUsage"
            type="number"
            placeholder="Kosong = tidak terbatas"
          />
          <Field
            label="Tanggal mulai"
            name="startsAt"
            type="date"
            placeholder=""
            hint="Kosong = mulai hari ini"
          />
          <Field
            label="Berlaku hingga"
            name="expiresAt"
            type="date"
            placeholder=""
            hint="Kosong = tidak ada batas waktu"
          />
        </div>

        <label className="flex items-center gap-3 rounded-2xl border border-zinc-200 bg-white px-4 py-3 text-sm font-bold text-zinc-700">
          <input
            type="checkbox"
            name="isActive"
            defaultChecked
            className="h-4 w-4 accent-blue-600"
          />
          Aktif di user app
        </label>

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
