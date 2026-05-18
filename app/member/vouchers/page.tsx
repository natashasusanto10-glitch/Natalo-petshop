import type { Metadata } from "next";
import Link from "next/link";
import { FiGift } from "react-icons/fi";
import { StickyBackTitle } from "@/components/StickyBackTitle";
import { formatRupiah } from "@/lib/format";
import { loadActiveMemberVouchers } from "@/lib/member-vouchers";
import { prisma } from "@/lib/prisma";
import { requireCustomerSession } from "@/lib/session-guards";
import { getVoucherDisabledReason } from "@/lib/voucher-helpers";

export const metadata: Metadata = { title: "Voucher Member" };

function formatDate(date: Date | null) {
  if (!date) return "Berlaku selamanya";
  return new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: "Asia/Jakarta",
  }).format(date);
}

function describeVoucher(voucher: {
  discountAmount: number | null;
  discountPercent: number | null;
}) {
  if (voucher.discountAmount && voucher.discountAmount > 0) {
    return `Voucher ${formatRupiah(voucher.discountAmount)}`;
  }
  if (voucher.discountPercent && voucher.discountPercent > 0) {
    return `Voucher ${voucher.discountPercent}%`;
  }
  return "Voucher Member";
}

export default async function MemberVouchersPage() {
  const session = await requireCustomerSession();
  const now = new Date();
  const [visibleVouchers, user, successfulOrderCount] = await Promise.all([
    loadActiveMemberVouchers(session.sub, now),
    prisma.user.findUnique({
      where: { id: session.sub },
      select: { id: true, createdAt: true },
    }),
    prisma.order.count({
      where: {
        userId: session.sub,
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
    }),
  ]);

  return (
    <main className="min-h-screen bg-slate-50">
      <StickyBackTitle label="Voucher Member" fallbackHref="/member" stickToTop />
      <div className="mx-auto max-w-2xl px-4 py-4 md:py-10">
        {visibleVouchers.length > 0 ? (
          <div className="space-y-3">
            {visibleVouchers.map((voucher) => {
              const disabledReason = getVoucherDisabledReason(
                voucher,
                0,
                {
                  isLoggedIn: true,
                  userId: session.sub,
                  createdAt: user?.createdAt ?? null,
                  successfulOrderCount,
                },
                now,
              );
              return (
                <article
                  key={voucher.id}
                  className="rounded-[20px] border border-slate-100 bg-white p-4 shadow-[0_8px_24px_rgba(16,24,40,0.06)]"
                >
                  <div className="flex items-start gap-3">
                    <span className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-[#EEF5FF] text-[#1677FF]">
                      <FiGift className="h-5 w-5" aria-hidden="true" />
                    </span>
                    <div className="min-w-0 flex-1">
                      <h2 className="text-sm font-black text-slate-950">
                        {describeVoucher(voucher)}
                      </h2>
                      <p className="mt-0.5 text-xs font-semibold leading-4 text-slate-500">
                        {voucher.description ?? "Voucher Member Natalo"}
                      </p>
                      <p className="mt-2 text-xs font-bold text-natalo-700">
                        {voucher.minimumOrder > 0
                          ? `Min. belanja ${formatRupiah(voucher.minimumOrder)}`
                          : "Tanpa minimum belanja"}
                      </p>
                    </div>
                  </div>
                  <div className="mt-3 flex items-center justify-between gap-3 border-t border-slate-100 pt-3">
                    <p className="text-xs font-semibold text-slate-500">
                      {voucher.expiresAt
                        ? `Berlaku sampai ${formatDate(voucher.expiresAt)}`
                        : "Berlaku selamanya"}
                    </p>
                    <span
                      className={`shrink-0 rounded-full px-3 py-1 text-[11px] font-black ${
                        disabledReason
                          ? "bg-slate-100 text-slate-500"
                          : "bg-emerald-50 text-emerald-600"
                      }`}
                    >
                      {disabledReason ?? "Siap dipakai"}
                    </span>
                  </div>
                </article>
              );
            })}
          </div>
        ) : (
          <section className="rounded-[20px] border border-dashed border-slate-200 bg-white p-8 text-center">
            <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-blue-50 text-natalo-600">
              <FiGift className="h-6 w-6" aria-hidden="true" />
            </span>
            <h1 className="mt-4 text-lg font-black text-slate-950">
              Belum ada voucher member
            </h1>
            <p className="mt-1 text-sm font-semibold leading-5 text-slate-500">
              Tukar loyalty poin untuk membuat voucher belanja baru.
            </p>
            <Link
              href="/account/loyalty/redeem"
              className="mt-5 inline-flex rounded-full bg-natalo-600 px-5 py-2.5 text-sm font-black text-white transition hover:bg-natalo-700"
            >
              Tukar Poin
            </Link>
          </section>
        )}
      </div>
    </main>
  );
}
