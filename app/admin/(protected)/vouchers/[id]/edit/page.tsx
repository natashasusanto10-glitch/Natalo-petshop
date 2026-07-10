import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { VoucherType, VoucherUserUsageLimitPeriod } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { AdminPage, Button } from "@/components/admin/ui";
import { isLoyaltyClaimVoucher } from "@/lib/voucher-kind";
import BrandTargetPicker from "../../BrandTargetPicker";

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
  const isLoyaltyClaim = isLoyaltyClaimVoucher(voucher);

  async function updateVoucher(formData: FormData) {
    "use server";

    const name = String(formData.get("name") || "").trim() || null;
    const code = String(formData.get("code") || "")
      .trim()
      .toUpperCase();
    const description =
      String(formData.get("description") || "").trim() || null;
    const typeRaw = String(formData.get("type") || voucher!.type).trim();
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
    const minimumOrder = parseInt(
      String(formData.get("minimumOrder") || "0"),
      10
    );
    const maxUsageRaw = String(formData.get("maxUsage") || "").trim();
    const maxUsage = maxUsageRaw ? parseInt(maxUsageRaw, 10) : null;
    const usageLimitPerUserRaw = String(
      formData.get("usageLimitPerUser") ?? ""
    ).trim();
    const usageLimitPeriodRaw = String(
      formData.get("usageLimitPeriod") ?? ""
    ).trim();
    const startsAtRaw = String(formData.get("startsAt") || "").trim();
    const startsAt = startsAtRaw ? new Date(startsAtRaw) : voucher!.startsAt;
    const expiresAtRaw = String(formData.get("expiresAt") || "").trim();
    const expiresAt = expiresAtRaw ? new Date(expiresAtRaw) : null;
    const sourceType =
      type === "PRIVATE_MANUAL_CODE" ? "SELLER_MANUAL" : "CUSTOMER";
    const eligibleUserIds = String(formData.get("eligibleUserIds") || "")
      .split(/[\s,]+/)
      .map((value) => value.trim())
      .filter(Boolean);
    const eligibleProductIds = String(formData.get("eligibleProductIds") || "")
      .split(/[\s,]+/)
      .map((value) => value.trim())
      .filter(Boolean);
    const eligibleCategoryIds = String(
      formData.get("eligibleCategoryIds") || ""
    )
      .split(/[\s,]+/)
      .map((value) => value.trim())
      .filter(Boolean);
    const eligibleBrandIds = String(formData.get("eligibleBrandIds") || "")
      .split(/[\s,]+/)
      .map((value) => value.trim())
      .filter(Boolean);

    if (
      type === "PUBLIC_FREE_SHIPPING" &&
      !discountAmount &&
      maxDiscountAmount
    ) {
      discountAmount = maxDiscountAmount;
    }

    if (!code) return;
    const kind:
      | "PRODUCT_DISCOUNT"
      | "FREE_SHIPPING"
      | "LOYALTY_CLAIM"
      | "MANUAL_PRIVATE" =
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
    const selectedUsageLimitPeriod = (
      Object.values(VoucherUserUsageLimitPeriod) as string[]
    ).includes(usageLimitPeriodRaw)
      ? (usageLimitPeriodRaw as VoucherUserUsageLimitPeriod)
      : VoucherUserUsageLimitPeriod.LIFETIME;
    const usageLimitPeriod =
      usageLimitPerUser <= 0
        ? VoucherUserUsageLimitPeriod.NONE
        : selectedUsageLimitPeriod === VoucherUserUsageLimitPeriod.NONE
        ? VoucherUserUsageLimitPeriod.LIFETIME
        : selectedUsageLimitPeriod;
    if (!isFreeShipping && !discountPercent && !discountAmount) return;

    // Form checkbox value — "on" = checked, null/missing = unchecked.
    const isActive = formData.get("isActive") === "on";

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
        eligibleBrandIds,
      },
    });

    redirect("/admin/vouchers");
  }

  // Format expiresAt untuk input type="date" (YYYY-MM-DD)
  const expiresAtValue = voucher.expiresAt
    ? voucher.expiresAt.toISOString().slice(0, 10)
    : "";
  const startsAtValue = voucher.startsAt
    ? voucher.startsAt.toISOString().slice(0, 10)
    : "";

  return (
    <AdminPage maxWidth="md">
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
      {isLoyaltyClaim && (
        <div className="mt-4 rounded-xl border border-blue-100 bg-blue-50 p-3 text-sm text-blue-700">
          Voucher ini berasal dari klaim loyalty point user. Admin tidak dapat
          membuat atau mengubah voucher menjadi tipe ini dari dashboard.
        </div>
      )}

      <form action={updateVoucher} className="mt-5 space-y-5 md:mt-8">
        <Field
          label="Nama voucher"
          name="name"
          defaultValue={voucher.name ?? ""}
        />
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
          <Field
            label="Maks. diskon / potongan ongkir"
            name="maxDiscountAmount"
            type="number"
            defaultValue={voucher.maxDiscountAmount?.toString() ?? ""}
            hint="Untuk persen atau gratis ongkir, isi batas maksimal potongan."
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
          <label className="block text-sm font-medium text-zinc-700">
            Tipe voucher Natalo
          </label>
          <select
            name="type"
            defaultValue={voucher.type}
            className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
          >
            <option value="PUBLIC_FREE_SHIPPING">Public Gratis Ongkir</option>
            <option value="PUBLIC_PRODUCT_DISCOUNT">
              Public Diskon Produk
            </option>
            <option value="LOYALTY_POINT_CLAIM">Loyalty Point Claim</option>
            <option value="PRIVATE_MANUAL_CODE">Private / Manual Code</option>
          </select>
          <p className="mt-1 text-xs text-zinc-600">
            Private voucher tidak muncul di list public dan hanya bisa dipakai
            lewat input kode manual.
          </p>
        </div>

        <Field
          label="Eligible user IDs untuk private voucher"
          name="eligibleUserIds"
          defaultValue={voucher.eligibleUserIds.join(", ")}
          placeholder="user_123, user_456"
          hint="Kosongkan jika private code boleh dipakai semua member login."
        />

        <BrandTargetPicker defaultSelectedIds={voucher.eligibleBrandIds} />

        <details className="rounded-2xl border border-zinc-200 bg-white px-4 py-3">
          <summary className="cursor-pointer text-sm font-medium text-zinc-700">
            Lanjutan — target produk / kategori spesifik
          </summary>
          <div className="mt-3 grid gap-4 sm:grid-cols-2">
            <Field
              label="Target product IDs"
              name="eligibleProductIds"
              defaultValue={voucher.eligibleProductIds.join(", ")}
              placeholder="product_123, product_456"
              hint="Untuk voucher SATU produk spesifik, bukan seluruh brand. Field Target brand di atas cukup untuk kebanyakan kasus."
            />
            <Field
              label="Target kategori IDs / slug"
              name="eligibleCategoryIds"
              defaultValue={voucher.eligibleCategoryIds.join(", ")}
              placeholder="cat-food, category_123"
              hint="Opsional. Bisa isi ID kategori atau slug kategori."
            />
          </div>
        </details>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Mulai berlaku"
            name="startsAt"
            type="date"
            defaultValue={startsAtValue}
          />
          <Field
            label="Kuota total voucher (semua user)"
            name="maxUsage"
            type="number"
            defaultValue={voucher.maxUsage?.toString() ?? ""}
            placeholder="Kosong = tidak dibatasi"
            hint={
              voucher.usedCount > 0
                ? `Tidak boleh < ${voucher.usedCount} (sudah terpakai). Kosong = tidak dibatasi.`
                : "Contoh: 100 berarti voucher hanya bisa dipakai 100 kali total oleh semua user."
            }
          />
          <Field
            label="Batas pemakaian per user"
            name="usageLimitPerUser"
            type="number"
            defaultValue={voucher.usageLimitPerUser.toString()}
            placeholder="0 = tanpa batas"
            hint="0 = user boleh pakai lagi di order berikutnya. 1 = tiap user hanya 1x."
          />
          <UsageLimitPeriodField defaultValue={voucher.usageLimitPeriod} />
          <Field
            label="Berlaku hingga"
            name="expiresAt"
            type="date"
            defaultValue={expiresAtValue}
            hint="Kosong = tidak ada batas waktu"
          />
        </div>

        {!isLoyaltyClaim && (
          <label className="flex items-center gap-3 rounded-2xl border border-zinc-200 bg-white px-4 py-3 text-sm font-bold text-zinc-700">
            <input
              type="checkbox"
              name="isActive"
              defaultChecked={voucher.isActive}
              className="h-4 w-4 accent-blue-600"
            />
            Aktif di user app
          </label>
        )}

        <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row">
          <Button href="/admin/vouchers" variant="secondary">
            Batal
          </Button>
          <Button type="submit" className="flex-1 sm:flex-none">
            Simpan perubahan
          </Button>
        </div>
      </form>
    </AdminPage>
  );
}

function UsageLimitPeriodField({ defaultValue }: { defaultValue: string }) {
  return (
    <div>
      <label className="block text-sm font-medium text-zinc-700">
        Periode batas per user
      </label>
      <select
        name="usageLimitPeriod"
        defaultValue={defaultValue}
        className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
      >
        <option value="NONE">Tanpa batas</option>
        <option value="LIFETIME">Selamanya</option>
        <option value="DAY">Per hari</option>
        <option value="WEEK">Per minggu</option>
        <option value="MONTH">Per bulan</option>
      </select>
      <p className="mt-1 text-xs text-zinc-600">
        Jika batas per user 0, sistem otomatis memakai tanpa batas.
      </p>
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
      {hint && <p className="mt-1 text-xs text-zinc-600">{hint}</p>}
    </div>
  );
}
