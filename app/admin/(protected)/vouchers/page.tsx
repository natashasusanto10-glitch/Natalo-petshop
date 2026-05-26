import Link from "next/link";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { ConfirmSubmitButton } from "@/components/ConfirmSubmitButton";
import { voucherUsageLimitLabel } from "@/lib/voucher-helpers";
import {
  isFreeShippingVoucher,
  isLoyaltyClaimVoucher,
  voucherKindLabel,
  voucherTargetUserLabel,
} from "@/lib/voucher-kind";
import {
  PageHeader,
  StatCard,
  EmptyState,
  Badge,
} from "@/components/admin/ui";

export default async function AdminVouchersPage() {
  const vouchers = await prisma.voucher.findMany({
    orderBy: { createdAt: "desc" },
  });

  async function toggleVoucher(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const current = formData.get("isActive") === "true";
    await prisma.voucher.update({ where: { id }, data: { isActive: !current } });
    revalidatePath("/admin/vouchers");
  }

  async function deleteVoucher(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const voucher = await prisma.voucher.findUnique({
      where: { id },
      select: { kind: true, userId: true, code: true },
    });
    if (voucher && isLoyaltyClaimVoucher(voucher)) {
      revalidatePath("/admin/vouchers");
      return;
    }
    await prisma.voucher.delete({ where: { id } });
    revalidatePath("/admin/vouchers");
  }

  const now = new Date();
  const counts = {
    PRODUCT_DISCOUNT: 0,
    FREE_SHIPPING: 0,
    LOYALTY_CLAIM: 0,
    MANUAL_PRIVATE: 0,
  };
  for (const voucher of vouchers) {
    if (isLoyaltyClaimVoucher(voucher)) counts.LOYALTY_CLAIM += 1;
    else if (voucher.kind === "FREE_SHIPPING") counts.FREE_SHIPPING += 1;
    else if (voucher.kind === "MANUAL_PRIVATE" || voucher.sourceType === "SELLER_MANUAL") {
      counts.MANUAL_PRIVATE += 1;
    } else counts.PRODUCT_DISCOUNT += 1;
  }

  return (
    <div className="mx-auto max-w-5xl px-4 py-5 md:py-10">
      <PageHeader
        title="Voucher"
        subtitle={`${vouchers.length} voucher total · kelola promo & loyalty reward`}
        actions={
          <Link
            href="/admin/vouchers/new"
            className="inline-flex items-center gap-1.5 rounded-full bg-natalo-600 px-4 py-2 text-xs font-bold text-white shadow-sm transition hover:bg-natalo-700 md:text-sm"
          >
            + Buat voucher
          </Link>
        }
      />

      <section className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          label="Diskon Produk"
          value={counts.PRODUCT_DISCOUNT}
          helper="Voucher potongan produk"
          variant="primary"
        />
        <StatCard
          label="Gratis Ongkir"
          value={counts.FREE_SHIPPING}
          helper="Voucher free shipping"
          variant="success"
        />
        <StatCard
          label="Claim Loyalty"
          value={counts.LOYALTY_CLAIM}
          helper="Reward dari point"
          variant="accent"
        />
        <StatCard
          label="Manual / Private"
          value={counts.MANUAL_PRIVATE}
          helper="Seller-issued private"
          variant="warning"
        />
      </section>

      <div className="mt-5 overflow-hidden rounded-2xl border border-zinc-200 bg-white md:mt-8">
        {vouchers.length === 0 ? (
          <EmptyState
            icon="🎟️"
            title="Belum ada voucher"
            description="Buat voucher pertama untuk mulai campaign promo atau loyalty reward."
            action={{ label: "Buat voucher pertama", href: "/admin/vouchers/new" }}
            size="full"
          />
        ) : (
          <div className="divide-y divide-zinc-100">
            {vouchers.map((v) => {
              const expired = v.expiresAt && v.expiresAt < now;
              const maxed = v.maxUsage !== null && v.usedCount >= v.maxUsage;
              const statusOk = v.isActive && !expired && !maxed;

              const discountParts: string[] = [];
              if (v.discountPercent) discountParts.push(`${v.discountPercent}%`);
              if (v.discountAmount) discountParts.push(formatRupiah(v.discountAmount));
              const typeLabel =
                v.type === "PUBLIC_FREE_SHIPPING"
                  ? "Public Gratis Ongkir"
                  : v.type === "PUBLIC_PRODUCT_DISCOUNT"
                    ? "Public Diskon Produk"
                    : v.type === "LOYALTY_POINT_CLAIM"
                      ? "Loyalty Reward"
                      : "Private Manual";
              const kindLabel = voucherKindLabel(v.kind);
              const scopeLabel =
                v.discountScope === "SHIPPING" ? "Ongkir" : "Produk";

              return (
                <div key={v.id} className="flex flex-col gap-4 p-4 transition hover:bg-zinc-50/60 md:flex-row md:flex-wrap md:items-start md:justify-between md:p-5">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-mono text-base font-black text-zinc-950">{v.code}</span>
                      <Badge variant="info">{typeLabel}</Badge>
                      <Badge
                        variant={
                          statusOk
                            ? "success"
                            : expired
                              ? "neutral"
                              : maxed
                                ? "warning"
                                : "danger"
                        }
                      >
                        {statusOk
                          ? "Aktif"
                          : expired
                            ? "Kedaluwarsa"
                            : maxed
                              ? "Habis"
                              : "Nonaktif"}
                      </Badge>
                      <Badge variant="info">{kindLabel}</Badge>
                      {v.kind === "PRODUCT_DISCOUNT" && (
                        <Badge variant="purple">
                          Target: {voucherTargetUserLabel(v.targetUser)}
                        </Badge>
                      )}
                    </div>

                    {v.description && (
                      <p className="mt-1 text-sm text-zinc-500">{v.description}</p>
                    )}

                    <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-zinc-500">
                      <span>Scope: <strong className="text-zinc-700">{scopeLabel}</strong></span>
                      <span>Diskon: <strong className="text-zinc-700">{discountParts.join(" + ") || "-"}</strong></span>
                      {v.maxDiscountAmount !== null && (
                        <span>Maks. potongan: <strong className="text-zinc-700">{formatRupiah(v.maxDiscountAmount)}</strong></span>
                      )}
                      {v.minimumOrder > 0 && (
                        <span>Min. belanja: <strong className="text-zinc-700">{formatRupiah(v.minimumOrder)}</strong></span>
                      )}
                      {v.kind === "PRODUCT_DISCOUNT" && v.targetUser === "NEW_MEMBER" && (
                        <span>
                          Rule: <strong className="text-zinc-700">
                            ≤{v.newMemberMaxAccountAgeDays ?? "-"} hari
                            {v.newMemberRequireNoSuccessfulOrder ? " · belum checkout" : ""}
                          </strong>
                        </span>
                      )}
                      <span>Batas per user: <strong className="text-zinc-700">{voucherUsageLimitLabel(v)}</strong></span>
                      <span>
                        Digunakan: <strong className="text-zinc-700">{v.usedCount}
                        {v.maxUsage !== null ? `/${v.maxUsage}` : ""}</strong>
                      </span>
                      {v.eligibleUserIds.length > 0 && (
                        <span>Eligible user: <strong className="text-zinc-700">{v.eligibleUserIds.length}</strong></span>
                      )}
                      {v.eligibleProductIds.length > 0 && (
                        <span>Target produk: <strong className="text-zinc-700">{v.eligibleProductIds.length}</strong></span>
                      )}
                      {v.eligibleCategoryIds.length > 0 && (
                        <span>Target kategori: <strong className="text-zinc-700">{v.eligibleCategoryIds.length}</strong></span>
                      )}
                      {v.expiresAt && (
                        <span>
                          Berlaku s/d: <strong className="text-zinc-700">
                            {v.expiresAt.toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric" })}
                          </strong>
                        </span>
                      )}
                    </div>
                  </div>

                  <div className="flex flex-wrap items-center gap-2">
                    {/* Edit */}
                    <Link
                      href={`/admin/vouchers/${v.id}/edit`}
                      className="rounded-full border border-zinc-200 px-3 py-1.5 text-xs font-bold text-zinc-700 hover:border-zinc-400 hover:bg-zinc-50"
                    >
                      ✏️ Edit
                    </Link>

                    {/* Toggle aktif/nonaktif */}
                    <form action={toggleVoucher}>
                      <input type="hidden" name="id" value={v.id} />
                      <input type="hidden" name="isActive" value={String(v.isActive)} />
                      <button
                        type="submit"
                        className={`rounded-full border px-3 py-1.5 text-xs font-bold ${
                          v.isActive
                            ? "border-amber-200 text-amber-700 hover:bg-amber-50"
                            : "border-green-200 text-green-700 hover:bg-green-50"
                        }`}
                      >
                        {v.isActive ? "Nonaktifkan" : "Aktifkan"}
                      </button>
                    </form>

                    {/* Hapus dengan konfirmasi */}
                    {isLoyaltyClaimVoucher(v) ? (
                      <span className="rounded-full border border-zinc-200 px-3 py-1.5 text-xs font-bold text-zinc-400">
                        Klaim user
                      </span>
                    ) : (
                      <form action={deleteVoucher}>
                        <input type="hidden" name="id" value={v.id} />
                        <ConfirmSubmitButton
                          className="rounded-full border border-red-100 px-3 py-1.5 text-xs font-bold text-red-500 hover:bg-red-50"
                          message={
                            v.usedCount > 0
                              ? `⚠️ Voucher "${v.code}" sudah dipakai ${v.usedCount} kali. Order yang sudah pakai voucher ini tidak terpengaruh, tapi voucher akan hilang dari daftar. Lanjutkan hapus?`
                              : `Hapus voucher "${v.code}"? Tindakan ini tidak bisa dibatalkan.`
                          }
                        >
                          🗑️ Hapus
                        </ConfirmSubmitButton>
                      </form>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
