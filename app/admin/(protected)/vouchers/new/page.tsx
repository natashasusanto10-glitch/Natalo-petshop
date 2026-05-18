import Link from "next/link";
import { redirect } from "next/navigation";
import { VoucherType } from "@prisma/client";
import { prisma } from "@/lib/prisma";

export default async function AdminVoucherNewPage() {
  async function createVoucher(formData: FormData) {
    "use server";

    const name = String(formData.get("name") || "").trim() || null;
    const code = String(formData.get("code") || "").trim().toUpperCase();
    const description = String(formData.get("description") || "").trim() || null;
    const typeRaw = String(formData.get("type") || "PUBLIC_PRODUCT_DISCOUNT").trim();
    const type = (Object.values(VoucherType) as string[]).includes(typeRaw)
      ? (typeRaw as VoucherType)
      : VoucherType.PUBLIC_PRODUCT_DISCOUNT;
    const visibility =
      type === "PRIVATE_MANUAL_CODE"
        ? "PRIVATE"
        : type === "LOYALTY_POINT_CLAIM"
          ? "USER_OWNED"
          : "PUBLIC";
    const discountScope =
      type === "PUBLIC_FREE_SHIPPING" ? "SHIPPING" : "PRODUCT";
    const discountPercent = formData.get("discountPercent")
      ? parseInt(String(formData.get("discountPercent")), 10)
      : null;
    let discountAmount = formData.get("discountAmount")
      ? parseInt(String(formData.get("discountAmount")), 10)
      : null;
    const maxDiscountAmount = formData.get("maxDiscountAmount")
      ? parseInt(String(formData.get("maxDiscountAmount")), 10)
      : null;
    const minimumOrder = parseInt(String(formData.get("minimumOrder") || "0"), 10);
    const maxUsageRaw = String(formData.get("maxUsage") || "").trim();
    const maxUsage = maxUsageRaw ? parseInt(maxUsageRaw, 10) : null;
    const usageLimitPerUserRaw = String(formData.get("usageLimitPerUser") ?? "").trim();
    const startsAtRaw = String(formData.get("startsAt") || "").trim();
    const startsAt = startsAtRaw ? new Date(startsAtRaw) : new Date();
    const expiresAtRaw = String(formData.get("expiresAt") || "").trim();
    const expiresAt = expiresAtRaw ? new Date(expiresAtRaw) : null;
    const sourceType = type === "PRIVATE_MANUAL_CODE" ? "SELLER_MANUAL" : "CUSTOMER";
    const eligibleUserIds = String(formData.get("eligibleUserIds") || "")
      .split(/[\s,]+/)
      .map((value) => value.trim())
      .filter(Boolean);
    const eligibleProductIds = String(formData.get("eligibleProductIds") || "")
      .split(/[\s,]+/)
      .map((value) => value.trim())
      .filter(Boolean);
    const eligibleCategoryIds = String(formData.get("eligibleCategoryIds") || "")
      .split(/[\s,]+/)
      .map((value) => value.trim())
      .filter(Boolean);

    if (type === "PUBLIC_FREE_SHIPPING" && !discountAmount && maxDiscountAmount) {
      discountAmount = maxDiscountAmount;
    }

    if (!code) return;
    // Derive `kind` dari `type` — kedua field tersimpan di DB untuk
    // backward compat (type lama vs kind baru). Mapping intuitive.
    const kind: "PRODUCT_DISCOUNT" | "FREE_SHIPPING" | "LOYALTY_CLAIM" | "MANUAL_PRIVATE" =
      type === "PUBLIC_FREE_SHIPPING"
        ? "FREE_SHIPPING"
        : type === "LOYALTY_POINT_CLAIM"
          ? "LOYALTY_CLAIM"
          : type === "PRIVATE_MANUAL_CODE"
            ? "MANUAL_PRIVATE"
            : "PRODUCT_DISCOUNT";
    const isFreeShipping = kind === "FREE_SHIPPING";
    const defaultUsageLimitPerUser =
      kind === "MANUAL_PRIVATE" || kind === "LOYALTY_CLAIM" ? 1 : 0;
    const parsedUsageLimitPerUser =
      usageLimitPerUserRaw === ""
        ? defaultUsageLimitPerUser
        : parseInt(usageLimitPerUserRaw, 10);
    const usageLimitPerUser = Number.isFinite(parsedUsageLimitPerUser)
      ? Math.max(0, parsedUsageLimitPerUser)
      : defaultUsageLimitPerUser;
    const usageLimitPeriod = usageLimitPerUser <= 0 ? "NONE" : "LIFETIME";
    if (!isFreeShipping && !discountPercent && !discountAmount) return;

    // Form checkbox — "on" = checked, null/missing = unchecked.
    const isActive = formData.get("isActive") === "on";

    const existing = await prisma.voucher.findUnique({ where: { code } });
    if (existing) redirect("/admin/vouchers/new?error=exists");

    await prisma.voucher.create({
      data: {
        name,
        code,
        description,
        discountPercent,
        discountAmount,
        maxDiscountAmount,
        minimumOrder,
        maxUsage,
        usageLimitPerUser,
        usageLimitPeriod,
        startsAt,
        expiresAt,
        isActive,
        sourceType,
        type,
        kind,
        visibility,
        discountType: discountPercent ? "PERCENTAGE" : "FIXED_AMOUNT",
        discountScope,
        eligibleUserIds,
        eligibleProductIds,
        eligibleCategoryIds,
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
          label="Nama voucher"
          name="name"
          placeholder="Contoh: Gratis Ongkir Natalo"
        />
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
          <Field
            label="Maks. diskon / potongan ongkir"
            name="maxDiscountAmount"
            type="number"
            placeholder="Contoh: 50000"
            hint="Untuk persen atau gratis ongkir, isi batas maksimal potongan."
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
          <label className="block text-sm font-medium text-zinc-700">Tipe voucher Natalo</label>
          <select
            name="type"
            defaultValue="PUBLIC_PRODUCT_DISCOUNT"
            className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
          >
            <option value="PUBLIC_FREE_SHIPPING">Public Gratis Ongkir</option>
            <option value="PUBLIC_PRODUCT_DISCOUNT">Public Diskon Produk</option>
            <option value="PRIVATE_MANUAL_CODE">Private / Manual Code</option>
          </select>
          <p className="mt-1 text-xs text-zinc-400">
            Voucher loyalty point dibuat otomatis dari halaman reward member,
            bukan dari form public admin ini.
          </p>
        </div>

        <Field
          label="Eligible user IDs untuk private voucher"
          name="eligibleUserIds"
          placeholder="user_123, user_456"
          hint="Kosongkan jika private code boleh dipakai semua member login."
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Target product IDs"
            name="eligibleProductIds"
            placeholder="product_123, product_456"
            hint="Opsional. Untuk voucher produk tertentu. Kosong = berlaku semua produk."
          />
          <Field
            label="Target kategori IDs / slug"
            name="eligibleCategoryIds"
            placeholder="cat-food, category_123"
            hint="Opsional. Bisa isi ID kategori atau slug kategori."
          />
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Mulai berlaku"
            name="startsAt"
            type="date"
            placeholder=""
            hint="Kosong = aktif mulai sekarang"
          />
          <Field
            label="Kuota total voucher (semua user)"
            name="maxUsage"
            type="number"
            placeholder="Kosong = tidak dibatasi"
            hint="Contoh: 100 berarti voucher hanya bisa dipakai 100 kali total oleh semua user."
          />
          <Field
            label="Batas pemakaian per user"
            name="usageLimitPerUser"
            type="number"
            defaultValue="0"
            placeholder="0 = tanpa batas"
            hint="0 = user boleh pakai lagi di order berikutnya. 1 = tiap user hanya 1x."
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
