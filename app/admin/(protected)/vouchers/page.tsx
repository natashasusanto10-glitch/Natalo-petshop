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
      <div className="flex flex-wrap items-end justify-between gap-3 md:gap-4">
        <div className="min-w-0">
          <Link href="/admin" className="hidden text-sm font-bold text-zinc-500 hover:text-zinc-950 md:inline">
            ← Kembali ke admin
          </Link>
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:mt-2 md:text-3xl">Voucher</h1>
          <p className="mt-1 text-sm text-zinc-500">{vouchers.length} voucher</p>
        </div>
        <Link
          href="/admin/vouchers/new"
          className="shrink-0 rounded-full bg-zinc-950 px-4 py-2 text-xs font-bold text-white md:px-5 md:py-3 md:text-sm"
        >
          + Buat voucher
        </Link>
      </div>

      <div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {[
          ["Diskon Produk", counts.PRODUCT_DISCOUNT],
          ["Gratis Ongkir", counts.FREE_SHIPPING],
          ["Claim Loyalty", counts.LOYALTY_CLAIM],
          ["Manual / Private", counts.MANUAL_PRIVATE],
        ].map(([label, value]) => (
          <div key={String(label)} className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
            <p className="text-xs font-bold uppercase tracking-wide text-zinc-400">{label}</p>
            <p className="mt-1 text-2xl font-black text-zinc-950">{value}</p>
          </div>
        ))}
      </div>

      <div className="mt-5 overflow-hidden rounded-2xl border border-zinc-200 md:mt-8 md:rounded-3xl">
        {vouchers.length === 0 ? (
          <div className="p-12 text-center text-sm text-zinc-500">
            <p className="text-2xl">🎟️</p>
            <p className="mt-3 font-semibold text-zinc-700">Belum ada voucher</p>
            <Link
              href="/admin/vouchers/new"
              className="mt-4 inline-flex rounded-full bg-zinc-950 px-5 py-2.5 text-sm font-bold text-white"
            >
              Buat sekarang
            </Link>
          </div>
        ) : (
          <div className="divide-y divide-zinc-100">
            {vouchers.map((v) => {
              const expired = v.expiresAt && v.expiresAt < now;
              const maxed = v.maxUsage !== null && v.usedCount >= v.maxUsage;
              const statusOk = v.isActive && !expired && !maxed;

              const discountParts: string[] = [];
              if (isFreeShippingVoucher(v)) discountParts.push("Gratis ongkir");
              else {
                if (v.discountPercent) discountParts.push(`${v.discountPercent}%`);
                if (v.discountAmount) discountParts.push(formatRupiah(v.discountAmount));
                if (v.maxDiscountAmount) discountParts.push(`max ${formatRupiah(v.maxDiscountAmount)}`);
              }
              const kindLabel = isLoyaltyClaimVoucher(v)
                ? voucherKindLabel("LOYALTY_CLAIM")
                : voucherKindLabel(v.kind);

              return (
                <div key={v.id} className="flex flex-col gap-4 p-4 md:flex-row md:flex-wrap md:items-start md:justify-between md:p-5">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-base font-bold text-zinc-950">{v.code}</span>
                      <span
                        className={`rounded-full px-2.5 py-0.5 text-xs font-bold ${
                          statusOk
                            ? "bg-green-100 text-green-700"
                            : expired
                            ? "bg-zinc-100 text-zinc-500"
                            : maxed
                            ? "bg-amber-100 text-amber-700"
                            : "bg-red-100 text-red-600"
                        }`}
                      >
                        {statusOk ? "Aktif" : expired ? "Kedaluwarsa" : maxed ? "Habis" : "Nonaktif"}
                      </span>
                      <span className="rounded-full bg-blue-50 px-2.5 py-0.5 text-xs font-bold text-blue-700">
                        {kindLabel}
                      </span>
                      {v.kind === "PRODUCT_DISCOUNT" && (
                        <span className="rounded-full bg-indigo-50 px-2.5 py-0.5 text-xs font-bold text-indigo-700">
                          Target: {voucherTargetUserLabel(v.targetUser)}
                        </span>
                      )}
                    </div>

                    {v.description && (
                      <p className="mt-1 text-sm text-zinc-500">{v.description}</p>
                    )}

                    <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-zinc-500">
                      <span>Diskon: <strong className="text-zinc-700">{discountParts.join(" + ") || "-"}</strong></span>
                      {v.userId && (
                        <span>User: <strong className="text-zinc-700">{v.userId}</strong></span>
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
                      <span>Limit/user: <strong className="text-zinc-700">{voucherUsageLimitLabel(v)}</strong></span>
                      <span>
                        Digunakan: <strong className="text-zinc-700">{v.usedCount}
                        {v.maxUsage !== null ? `/${v.maxUsage}` : ""}</strong>
                      </span>
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
