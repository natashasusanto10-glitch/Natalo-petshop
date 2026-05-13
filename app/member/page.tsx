import Link from "next/link";
import {
  FiBell,
  FiCheckCircle,
  FiChevronRight,
  FiCreditCard,
  FiGift,
  FiHeart,
  FiHelpCircle,
  FiHome,
  FiLogOut,
  FiMapPin,
  FiPackage,
  FiShield,
  FiShoppingBag,
  FiTruck,
  FiUser,
} from "react-icons/fi";
import { LogoutButton } from "@/components/LogoutButton";
import { prisma } from "@/lib/prisma";
import { requireCustomerSession } from "@/lib/session-guards";

function formatMemberSince(date: Date | null | undefined) {
  if (!date) return "-";
  return new Intl.DateTimeFormat("id-ID", {
    month: "short",
    year: "numeric",
    timeZone: "Asia/Jakarta",
  }).format(date);
}

function orderCount(
  groups: Array<{ status: string; _count: { _all: number } }>,
  statuses: string[],
) {
  return groups
    .filter((group) => statuses.includes(group.status))
    .reduce((total, group) => total + group._count._all, 0);
}

function CountBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span className="absolute right-3 top-3 grid h-5 min-w-5 place-items-center rounded-full bg-red-500 px-1 text-[10px] font-black leading-none text-white">
      {count > 99 ? "99+" : count}
    </span>
  );
}

function OrderStatusItem({
  href,
  icon: Icon,
  label,
  count,
}: {
  href: string;
  icon: typeof FiPackage;
  label: string;
  count: number;
}) {
  return (
    <Link
      href={href}
      className="relative flex min-w-0 flex-col items-center gap-2 rounded-[18px] bg-slate-50 px-2 py-3 text-center transition active:scale-[0.98]"
    >
      <CountBadge count={count} />
      <span className="grid h-10 w-10 place-items-center rounded-2xl bg-white text-natalo-600 shadow-sm">
        <Icon className="h-5 w-5" aria-hidden="true" />
      </span>
      <span className="text-[12px] font-extrabold leading-tight text-slate-700">{label}</span>
    </Link>
  );
}

function MenuCard({
  href,
  icon: Icon,
  title,
  description,
}: {
  href: string;
  icon: typeof FiPackage;
  title: string;
  description: string;
}) {
  return (
    <Link
      href={href}
      className="flex min-h-[108px] flex-col justify-between rounded-[18px] border border-slate-100 bg-white p-4 shadow-[0_8px_24px_rgba(16,24,40,0.06)] transition active:scale-[0.98]"
    >
      <span className="grid h-10 w-10 place-items-center rounded-2xl bg-[#EEF5FF] text-[#1677FF]">
        <Icon className="h-5 w-5" aria-hidden="true" />
      </span>
      <span>
        <span className="block text-sm font-black text-[#101A33]">{title}</span>
        <span className="mt-0.5 block text-xs font-semibold leading-4 text-slate-500">
          {description}
        </span>
      </span>
    </Link>
  );
}

function SettingsRow({
  href,
  icon: Icon,
  title,
  description,
}: {
  href: string;
  icon: typeof FiBell;
  title: string;
  description: string;
}) {
  return (
    <Link
      href={href}
      className="flex items-center gap-3 px-4 py-4 transition active:bg-slate-50"
    >
      <span className="grid h-10 w-10 shrink-0 place-items-center rounded-2xl bg-slate-50 text-natalo-600">
        <Icon className="h-5 w-5" aria-hidden="true" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-black text-slate-950">{title}</span>
        <span className="mt-0.5 block text-xs font-semibold leading-4 text-slate-500">
          {description}
        </span>
      </span>
      <FiChevronRight className="h-5 w-5 shrink-0 text-slate-300" aria-hidden="true" />
    </Link>
  );
}

export default async function MemberPage() {
  const session = await requireCustomerSession();
  const now = new Date();

  const [totalPoints, orderGroups, voucherCandidates, user] = await Promise.all([
    prisma.customerPoint.aggregate({
      where: { userId: session.sub },
      _sum: { points: true },
    }),
    prisma.order.groupBy({
      by: ["status"],
      where: { userId: session.sub },
      _count: { _all: true },
    }),
    prisma.voucher.findMany({
      where: {
        userId: session.sub,
        isActive: true,
        startsAt: { lte: now },
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      select: { maxUsage: true, usedCount: true },
    }),
    prisma.user.findUnique({
      where: { id: session.sub },
      select: { birthDate: true, birthdayVoucherYear: true, createdAt: true, name: true },
    }),
  ]);

  const points = totalPoints?._sum.points ?? 0;
  const activeVoucherCount = voucherCandidates.filter(
    (voucher) => voucher.maxUsage === null || voucher.usedCount < voucher.maxUsage,
  ).length;
  const unpaidCount = orderCount(orderGroups, ["PENDING"]);
  const processingCount = orderCount(orderGroups, ["PAID", "PROCESSING"]);
  const shippedCount = orderCount(orderGroups, ["SHIPPED"]);
  const doneCount = orderCount(orderGroups, ["DELIVERED"]);
  const displayName = user?.name ?? session.name ?? "Member";
  const initial = displayName.charAt(0).toUpperCase() || "N";
  const memberSince = formatMemberSince(user?.createdAt);

  let birthdayVoucherCode: string | null = null;

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

  return (
    <main className="min-h-screen bg-slate-50 px-4 pb-[calc(120px+env(safe-area-inset-bottom))] pt-4">
      <div className="mx-auto max-w-4xl space-y-5">
        <section className="overflow-hidden rounded-[24px] bg-gradient-to-br from-[#1677FF] to-[#0F4EAF] p-5 text-white shadow-[0_8px_24px_rgba(16,24,40,0.08)]">
          <div className="flex items-start gap-4">
            <div className="relative grid h-16 w-16 shrink-0 place-items-center rounded-full bg-white/18 text-2xl font-black ring-1 ring-white/20">
              {initial}
              <span className="absolute -right-1 -top-1 grid h-7 w-7 place-items-center rounded-full bg-white text-sm text-[#1677FF] shadow-sm">
                <FiCheckCircle className="h-4 w-4" aria-hidden="true" />
              </span>
            </div>
            <div className="min-w-0 flex-1">
              <span className="inline-flex rounded-full bg-white/16 px-3 py-1 text-xs font-black text-white ring-1 ring-white/20">
                Member Resmi
              </span>
              <h1 className="mt-2 text-2xl font-black leading-tight tracking-tight">
                Halo, {displayName}!
              </h1>
              <p className="mt-1 text-sm font-semibold leading-5 text-blue-50">
                Senang melihatmu kembali di Natalo 🐾
              </p>
              <Link
                href="/member/profile"
                className="mt-4 inline-flex rounded-2xl bg-white px-4 py-2 text-sm font-black text-[#1677FF] shadow-sm transition active:scale-[0.98]"
              >
                Edit Profil
              </Link>
            </div>
          </div>

          <div className="mt-5 grid grid-cols-3 gap-2 border-t border-white/18 pt-4">
            <div>
              <p className="text-2xl font-black leading-none">{points.toLocaleString("id-ID")}</p>
              <p className="mt-1 text-[11px] font-bold text-blue-50">Loyalty Point</p>
            </div>
            <div>
              <p className="text-sm font-black leading-tight">{memberSince}</p>
              <p className="mt-1 text-[11px] font-bold text-blue-50">Member sejak</p>
            </div>
            <Link
              href="/member/points"
              className="flex items-center justify-between gap-1 rounded-2xl bg-white/12 px-3 py-2 text-left ring-1 ring-white/16"
            >
              <span>
                <span className="block text-sm font-black leading-tight">Riwayat</span>
                <span className="block text-[11px] font-bold text-blue-50">Poin</span>
              </span>
              <FiChevronRight className="h-4 w-4 shrink-0" aria-hidden="true" />
            </Link>
          </div>
        </section>

        {birthdayVoucherCode && (
          <section className="rounded-[20px] border border-pink-200 bg-pink-50 p-4">
            <p className="text-sm font-black text-pink-700">Voucher ulang tahun aktif</p>
            <p className="mt-1 text-sm font-semibold leading-5 text-pink-900">
              Kode {birthdayVoucherCode} memberi diskon 15% dan berlaku 7 hari.
            </p>
          </section>
        )}

        <section className="rounded-[20px] border border-slate-100 bg-white p-4 shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
          <div className="flex items-center justify-between gap-3">
            <h2 className="text-lg font-black text-[#101A33]">Pesanan Saya</h2>
            <Link href="/member/orders" className="inline-flex items-center gap-1 text-sm font-black text-natalo-600">
              Lihat Semua
              <FiChevronRight className="h-4 w-4" aria-hidden="true" />
            </Link>
          </div>
          <div className="mt-4 grid grid-cols-4 gap-2">
            <OrderStatusItem href="/member/orders" icon={FiCreditCard} label="Belum Bayar" count={unpaidCount} />
            <OrderStatusItem href="/member/orders" icon={FiPackage} label="Diproses" count={processingCount} />
            <OrderStatusItem href="/member/orders" icon={FiTruck} label="Dikirim" count={shippedCount} />
            <OrderStatusItem href="/member/orders" icon={FiCheckCircle} label="Selesai" count={doneCount} />
          </div>
        </section>

        <section>
          <h2 className="px-1 text-lg font-black text-[#101A33]">Menu Transaksi</h2>
          <div className="mt-3 grid grid-cols-2 gap-3">
            <MenuCard href="/member/orders" icon={FiShoppingBag} title="Pesanan Saya" description="Lihat riwayat pesanan" />
            <MenuCard href="/wishlist" icon={FiHeart} title="Wishlist" description="Produk yang kamu favoritkan" />
            <MenuCard
              href="/cart"
              icon={FiGift}
              title="Voucher Member"
              description={
                activeVoucherCount > 0
                  ? `${activeVoucherCount} voucher aktif`
                  : "Voucher & promo khusus member"
              }
            />
            <MenuCard href="/akun/alamat" icon={FiMapPin} title="Alamat" description="Kelola alamat pengiriman" />
          </div>
        </section>

        <section>
          <h2 className="px-1 text-lg font-black text-[#101A33]">Akun & Pengaturan</h2>
          <div className="mt-3 divide-y divide-slate-100 overflow-hidden rounded-[20px] border border-slate-100 bg-white shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
            <SettingsRow href="/akun/pengaturan/notifikasi" icon={FiBell} title="Pengaturan Notifikasi" description="Atur preferensi notifikasi" />
            <SettingsRow href="/bantuan" icon={FiHelpCircle} title="Bantuan" description="Pusat bantuan dan FAQ" />
            <SettingsRow href="/akun/sesi-aktif" icon={FiShield} title="Keamanan & sesi aktif" description="Kelola keamanan akun dan perangkat aktif" />
            <SettingsRow href="/tentang-kami" icon={FiHome} title="Tentang Natalo" description="Informasi aplikasi, syarat & ketentuan" />
          </div>
        </section>

        <LogoutButton
          redirectTo="/member/login"
          className="flex w-full items-center gap-3 rounded-[20px] border border-red-100 bg-white p-4 text-left text-red-600 shadow-[0_8px_24px_rgba(16,24,40,0.06)] hover:border-red-200 hover:bg-red-50 hover:text-red-600"
        >
          <span className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-red-50 text-red-500">
            <FiLogOut className="h-5 w-5" aria-hidden="true" />
          </span>
          <span className="min-w-0 flex-1">
            <span className="block text-sm font-black">Keluar dari akun</span>
            <span className="mt-0.5 block text-xs font-semibold text-red-400">
              Logout dari akun Natalo Petshop
            </span>
          </span>
          <FiChevronRight className="h-5 w-5 shrink-0 text-red-300" aria-hidden="true" />
        </LogoutButton>
      </div>
    </main>
  );
}
