import Link from "next/link";
import { ClaimVoucherButton } from "@/components/ClaimVoucherButton";
import { LogoutButton } from "@/components/LogoutButton";
import { getSession } from "@/lib/auth";
import { formatRupiah } from "@/lib/format";
import { prisma } from "@/lib/prisma";

function formatDate(date: Date | null) {
  if (!date) return "Tanpa batas waktu";
  return new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(date);
}

function formatVoucherValue(voucher: {
  discountPercent: number | null;
  discountAmount: number | null;
}) {
  const values: string[] = [];
  if (voucher.discountPercent) values.push(`${voucher.discountPercent}%`);
  if (voucher.discountAmount) values.push(formatRupiah(voucher.discountAmount));
  return values.length > 0 ? values.join(" + ") : "Diskon";
}

export default async function MemberPage() {
  const session = await getSession("CUSTOMER");

  const totalPoints = session
    ? await prisma.customerPoint.aggregate({
        where: { userId: session.sub },
        _sum: { points: true },
      })
    : null;

  const points = totalPoints?._sum.points ?? 0;
  const now = new Date();

  const vouchers = session
    ? (
        await prisma.voucher.findMany({
          where: {
            userId: session.sub,
            isActive: true,
            startsAt: { lte: now },
            OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
          },
          orderBy: [{ expiresAt: "asc" }, { createdAt: "desc" }],
          take: 5,
        })
      ).filter((voucher) => voucher.maxUsage === null || voucher.usedCount < voucher.maxUsage)
    : [];

  let birthdayVoucherCode: string | null = null;
  if (session) {
    const user = await prisma.user.findUnique({
      where: { id: session.sub },
      select: { birthDate: true, birthdayVoucherYear: true },
    });

    if (user?.birthDate) {
      const today = new Date();
      const birthDate = user.birthDate;
      const isBirthday =
        birthDate.getDate() === today.getDate() &&
        birthDate.getMonth() === today.getMonth();
      const currentYear = today.getFullYear();
      const alreadyClaimedThisYear = user.birthdayVoucherYear === currentYear;

      if (isBirthday) {
        const code = `BDAY-${session.sub.slice(-6).toUpperCase()}-${currentYear}`;
        if (!alreadyClaimedThisYear) {
          const expiresAt = new Date(today);
          expiresAt.setDate(expiresAt.getDate() + 7);
          await prisma.$transaction([
            prisma.voucher.upsert({
              where: { code },
              create: {
                code,
                description: `Voucher ulang tahun ${currentYear}`,
                discountPercent: 15,
                minimumOrder: 0,
                maxUsage: 1,
                expiresAt,
                isActive: true,
                userId: session.sub,
              },
              update: { userId: session.sub },
            }),
            prisma.user.update({
              where: { id: session.sub },
              data: { birthdayVoucherYear: currentYear },
            }),
          ]);
        }
        birthdayVoucherCode = code;
      }
    }
  }

  return (
    <div className="mx-auto max-w-4xl px-4 py-4 md:py-10">
      <div className="overflow-hidden rounded-3xl bg-blue-500 p-5 text-white md:p-8">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="flex items-center gap-3 md:gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-white/20 text-2xl font-black md:h-16 md:w-16 md:text-3xl">
              {session?.name?.charAt(0)?.toUpperCase() ?? "N"}
            </div>
            <div>
              <p className="text-xs text-blue-100 md:text-sm">Member resmi</p>
              <h1 className="mt-0.5 text-xl font-black md:text-2xl">
                Halo, {session?.name ?? "Member"}!
              </h1>
            </div>
          </div>
          <LogoutButton
            redirectTo="/member/login"
            className="border-white/30 text-white hover:border-white hover:text-white"
          />
        </div>
      </div>

      {birthdayVoucherCode && (
        <div className="mt-6 rounded-2xl border border-pink-200 bg-pink-50 p-5">
          <p className="text-sm font-semibold text-pink-700">
            Selamat ulang tahun!
          </p>
          <p className="mt-1 text-sm text-gray-700">
            Voucher khusus untukmu:{" "}
            <span className="font-mono font-bold text-pink-700">
              {birthdayVoucherCode}
            </span>{" "}
            - diskon 15%, berlaku 7 hari.
          </p>
        </div>
      )}

      <div className="mt-6 rounded-2xl border border-blue-100 bg-blue-50 p-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-sm font-semibold text-blue-700">⭐ Loyalty Poin</p>
            <p className="mt-2 text-3xl font-black text-gray-900">
              {points.toLocaleString("id-ID")}
            </p>
            <p className="mt-1 text-sm text-gray-500">
              1 poin setiap Rp20.000 belanja.
            </p>
          </div>
          <Link
            href="/member/points"
            className="shrink-0 rounded-full bg-white px-3 py-1.5 text-xs font-bold text-blue-600 ring-1 ring-blue-200 transition hover:ring-blue-300"
          >
            History →
          </Link>
        </div>
        <ClaimVoucherButton totalPoints={points} />
      </div>

      <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { href: "/member/orders", icon: "📦", label: "Pesanan Saya" },
          { href: "/member/profile", icon: "👤", label: "Profil" },
          { href: "/wishlist", icon: "❤️", label: "Wishlist" },
          { href: "#voucher-member", icon: "🎟️", label: "Voucher Member" },
        ].map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="flex flex-col items-center gap-2 rounded-2xl border border-gray-100 bg-white p-4 text-center shadow-sm transition hover:border-blue-200 hover:shadow-md"
          >
            <span className="flex h-9 w-9 items-center justify-center rounded-full bg-blue-50 text-sm font-black text-blue-600">
              {item.icon}
            </span>
            <span className="text-xs font-semibold text-gray-700">
              {item.label}
            </span>
          </Link>
        ))}
      </div>

      <div className="mt-6 grid gap-4 sm:grid-cols-2">
        <div id="voucher-member" className="scroll-mt-24 rounded-2xl border border-blue-100 bg-blue-50 p-5">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-sm font-semibold text-blue-700">
                Voucher Member
              </p>
              <p className="mt-2 font-bold text-gray-900">
                Voucher yang bisa dipakai
              </p>
            </div>
            <Link
              href="/checkout"
              className="rounded-full bg-white px-3 py-1 text-xs font-bold text-blue-600 ring-1 ring-blue-100 hover:ring-blue-200"
            >
              Pakai
            </Link>
          </div>

          {vouchers.length > 0 ? (
            <div className="mt-4 space-y-2">
              {vouchers.map((voucher) => (
                <div
                  key={voucher.id}
                  className="rounded-2xl bg-white p-3 ring-1 ring-blue-100"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate font-mono text-sm font-black text-blue-600">
                        {voucher.code}
                      </p>
                      <p className="mt-1 text-xs font-semibold text-gray-700">
                        {formatVoucherValue(voucher)}
                        {voucher.minimumOrder > 0
                          ? ` - min. belanja ${formatRupiah(voucher.minimumOrder)}`
                          : ""}
                      </p>
                    </div>
                    <span className="shrink-0 rounded-full bg-blue-100 px-2 py-1 text-[11px] font-bold text-blue-700">
                      Aktif
                    </span>
                  </div>
                  <p className="mt-2 text-xs text-gray-500">
                    Expired: {formatDate(voucher.expiresAt)}
                  </p>
                  {voucher.description && (
                    <p className="mt-1 line-clamp-2 text-xs text-gray-400">
                      {voucher.description}
                    </p>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <p className="mt-3 text-sm text-gray-500">
              Belum ada voucher aktif. Tukar loyalty poin untuk membuat voucher
              baru.
            </p>
          )}
        </div>
        <div className="rounded-2xl border border-blue-100 bg-blue-50 p-5">
          <p className="text-sm font-semibold text-blue-700">Notifikasi Order</p>
          <p className="mt-2 font-bold text-gray-900">Pantau pesananmu</p>
          <p className="mt-1 text-sm text-gray-500">
            Detail pesanan lengkap tersedia di menu Pesanan Saya.
          </p>
        </div>
      </div>

      <div className="mt-8 border-t border-zinc-100 pt-6 text-center text-xs">
        <Link
          href="/akun/sesi-aktif"
          className="font-semibold text-blue-600 hover:underline"
        >
          🔐 Keamanan & sesi aktif
        </Link>
        <span className="mx-2 text-zinc-300">·</span>
        <Link
          href="/akun/hapus-akun"
          className="font-semibold text-red-600 hover:underline"
        >
          🗑️ Hapus akun
        </Link>
        <span className="mx-2 text-zinc-300">·</span>
        <Link
          href="/tentang-kami"
          className="font-semibold text-zinc-500 hover:text-blue-600 hover:underline"
        >
          Tentang Kami
        </Link>
      </div>
    </div>
  );
}
