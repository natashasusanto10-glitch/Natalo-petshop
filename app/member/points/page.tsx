import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export const metadata: Metadata = { title: "Loyalty Poin" };

function formatDate(date: Date) {
  return new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Asia/Jakarta",
  }).format(date);
}

const SOURCE_LABEL: Record<string, string> = {
  ORDER: "Belanja",
  ORDER_DELIVERED: "Order selesai",
  CLAIM: "Tukar voucher",
  ADJUST: "Penyesuaian admin",
  REFERRAL: "Referral teman",
};

export default async function MemberPointsPage() {
  const session = await getSession("CUSTOMER");
  if (!session) redirect("/member/login");

  const [aggregate, history] = await Promise.all([
    prisma.customerPoint.aggregate({
      where: { userId: session.sub },
      _sum: { points: true },
    }),
    prisma.customerPoint.findMany({
      where: { userId: session.sub },
      orderBy: { createdAt: "desc" },
      take: 100,
    }),
  ]);

  const total = aggregate?._sum.points ?? 0;
  const earned = history.filter((h) => h.points > 0).reduce((s, h) => s + h.points, 0);
  const redeemed = history.filter((h) => h.points < 0).reduce((s, h) => s + h.points, 0);

  return (
    <div className="mx-auto max-w-2xl px-4 py-4 md:py-10">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-black text-gray-900 md:text-2xl">Loyalty Poin</h1>
        <Link
          href="/member"
          className="text-sm font-semibold text-orange-500 hover:underline"
        >
          ← Kembali
        </Link>
      </div>

      {/* Total balance card */}
      <div className="mt-4 overflow-hidden rounded-2xl bg-gradient-to-br from-orange-500 to-orange-600 p-5 text-white shadow-sm md:mt-6 md:p-6">
        <p className="text-xs uppercase tracking-wider text-orange-100">Total Saldo Poin</p>
        <p className="mt-2 text-4xl font-black md:text-5xl">{total.toLocaleString("id-ID")}</p>
        <p className="mt-1 text-xs text-orange-100">
          1 poin setiap Rp20.000 belanja · 1 poin = Rp100 voucher
        </p>

        <div className="mt-4 grid grid-cols-2 gap-3 border-t border-white/20 pt-4 text-sm">
          <div>
            <p className="text-xs text-orange-100">Total Diperoleh</p>
            <p className="mt-1 font-black">+{earned.toLocaleString("id-ID")}</p>
          </div>
          <div>
            <p className="text-xs text-orange-100">Total Ditukar</p>
            <p className="mt-1 font-black">{redeemed.toLocaleString("id-ID")}</p>
          </div>
        </div>
      </div>

      {/* CTA: claim voucher */}
      {total >= 50 && (
        <Link
          href="/member"
          className="mt-4 flex items-center justify-between gap-3 rounded-2xl border border-orange-200 bg-orange-50 p-4 transition hover:border-orange-300"
        >
          <div>
            <p className="text-sm font-bold text-orange-700">🎁 Tukar jadi voucher</p>
            <p className="mt-0.5 text-xs text-orange-600">
              Min. 50 poin (= Rp5.000 diskon). Klaim di halaman member.
            </p>
          </div>
          <span className="text-sm font-bold text-orange-700">Tukar →</span>
        </Link>
      )}

      {/* History list */}
      <div className="mt-6">
        <h2 className="text-lg font-black text-gray-900">History</h2>
        <p className="mt-1 text-xs text-gray-500">100 transaksi terakhir</p>

        {history.length > 0 ? (
          <div className="mt-3 divide-y divide-gray-100 rounded-2xl border border-gray-100 bg-white shadow-sm">
            {history.map((item) => {
              const isEarn = item.points > 0;
              return (
                <div
                  key={item.id}
                  className="flex items-center justify-between gap-3 p-4"
                >
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-bold text-gray-900">
                      {SOURCE_LABEL[item.source] ?? item.source}
                    </p>
                    <p className="mt-0.5 text-xs text-gray-500">
                      {formatDate(item.createdAt)}
                    </p>
                  </div>
                  <p
                    className={`shrink-0 text-base font-black tabular-nums ${
                      isEarn ? "text-emerald-600" : "text-red-500"
                    }`}
                  >
                    {isEarn ? "+" : ""}
                    {item.points.toLocaleString("id-ID")}
                  </p>
                </div>
              );
            })}
          </div>
        ) : (
          <div className="mt-3 rounded-2xl border border-dashed border-gray-200 p-8 text-center">
            <span className="text-4xl">📊</span>
            <p className="mt-3 text-sm font-semibold text-gray-600">
              Belum ada transaksi poin.
            </p>
            <p className="mt-1 text-xs text-gray-400">
              Mulai belanja untuk dapatkan poin pertama!
            </p>
            <Link
              href="/products"
              className="mt-4 inline-flex rounded-full bg-orange-500 px-5 py-2 text-sm font-bold text-white transition hover:bg-orange-600"
            >
              Belanja sekarang
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}
