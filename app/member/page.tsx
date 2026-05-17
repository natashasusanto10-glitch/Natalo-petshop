import Link from "next/link";
import {
  FiBell,
  FiCheckCircle,
  FiChevronRight,
  FiCreditCard,
  FiGift,
  FiHeart,
  FiMapPin,
  FiPackage,
  FiPlayCircle,
  FiPlus,
  FiSettings,
  FiShoppingBag,
  FiStar,
  FiTag,
  FiTruck,
} from "react-icons/fi";
import type { IconType } from "react-icons";
import { AccountProfileAvatar } from "@/components/account/AccountProfileAvatar";
import { PageStatusBar } from "@/components/PageStatusBar";
import { loadActiveMemberVouchers } from "@/lib/member-vouchers";
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
    <span className="absolute right-2 top-2 grid h-5 min-w-5 place-items-center rounded-full bg-red-500 px-1 text-[10px] font-black leading-none text-white">
      {count > 9 ? "9+" : count}
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
  icon: IconType;
  label: string;
  count: number;
}) {
  return (
    <Link
      href={href}
      className="relative flex min-w-0 flex-col items-center gap-2 rounded-[18px] bg-slate-50 px-2 py-3 text-center transition active:scale-[0.98]"
    >
      <CountBadge count={count} />
      <span className="grid h-10 w-10 place-items-center rounded-2xl bg-[#EAF2FF] text-natalo-600">
        <Icon className="h-5 w-5" aria-hidden="true" />
      </span>
      <span className="text-[12px] font-extrabold leading-tight text-slate-700">{label}</span>
    </Link>
  );
}

function TransactionMenuItem({
  href,
  icon: Icon,
  title,
  description,
}: {
  href: string;
  icon: IconType;
  title: string;
  description: string;
}) {
  return (
    <Link
      href={href}
      className="flex min-h-[104px] flex-col justify-between rounded-[20px] border border-slate-100 bg-white p-4 shadow-[0_8px_24px_rgba(16,24,40,0.05)] transition active:scale-[0.98]"
    >
      <span className="grid h-11 w-11 place-items-center rounded-2xl bg-[#EAF2FF] text-natalo-600">
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

function FeedListItem({
  href,
  icon: Icon,
  title,
  subtitle,
  accent,
  badgeCount,
}: {
  href: string;
  icon: IconType;
  title: string;
  subtitle: string;
  accent?: boolean;
  badgeCount?: number;
}) {
  return (
    <Link
      href={href}
      className="flex items-center gap-3 px-4 py-4 transition active:bg-slate-50"
    >
      <span className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-[#EAF2FF] text-natalo-600">
        <Icon className="h-5 w-5" aria-hidden="true" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-2">
          <span
            className={`block text-sm font-black ${
              accent ? "text-natalo-700" : "text-slate-950"
            }`}
          >
            {title}
          </span>
          {badgeCount ? (
            <span className="grid h-5 min-w-5 place-items-center rounded-full bg-red-500 px-1 text-[10px] font-black leading-none text-white">
              {badgeCount > 9 ? "9+" : badgeCount}
            </span>
          ) : null}
        </span>
        <span className="mt-0.5 block text-xs font-semibold leading-4 text-slate-500">
          {subtitle}
        </span>
      </span>
      <FiChevronRight className="h-5 w-5 shrink-0 text-slate-300" aria-hidden="true" />
    </Link>
  );
}

export default async function MemberPage() {
  const session = await requireCustomerSession();
  const recentDoneSince = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

  const [totalPoints, orderGroups, recentDoneCount, user, pendingFeedPostCount] =
    await Promise.all([
      prisma.customerPoint.aggregate({
        where: { userId: session.sub },
        _sum: { points: true },
      }),
      prisma.order.groupBy({
        by: ["status"],
        where: { userId: session.sub },
        _count: { _all: true },
      }),
      prisma.order.count({
        where: {
          userId: session.sub,
          status: "DELIVERED",
          updatedAt: { gte: recentDoneSince },
        },
      }),
      prisma.user.findUnique({
        where: { id: session.sub },
        select: {
          id: true,
          birthDate: true,
          birthdayVoucherYear: true,
          createdAt: true,
          name: true,
        },
      }),
      prisma.feedPost.count({
        where: {
          authorId: session.sub,
          authorRole: "CUSTOMER",
          kind: "COMMUNITY",
          status: "PENDING_REVIEW",
          deletedAt: null,
        },
      }),
    ]);

  const points = totalPoints?._sum.points ?? 0;
  const unpaidCount = orderCount(orderGroups, ["PENDING"]);
  const processingCount = orderCount(orderGroups, ["PAID", "PROCESSING"]);
  const shippedCount = orderCount(orderGroups, ["SHIPPED"]);
  const doneCount = recentDoneCount;
  const displayName = user?.name ?? session.name ?? "Member";
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

  const activeMemberVouchers = await loadActiveMemberVouchers(session.sub);
  const activeVoucherCount = activeMemberVouchers.length;
  const voucherSubtitle =
    activeVoucherCount > 0
      ? `${activeVoucherCount} voucher aktif`
      : "Belum ada voucher aktif";

  return (
    <main className="min-h-screen bg-[#F6F9FF] pb-[calc(112px+env(safe-area-inset-bottom))]">
      <PageStatusBar
        iconColor="dark"
        themeColor="#ffffff"
        nativeBackgroundColor="#ffffff"
        overlaysWebView={false}
      />

      <header className="sticky top-0 z-[1050] border-b border-slate-100/80 bg-white px-5 pb-3 shadow-[0_8px_24px_rgba(15,23,42,0.05)] [padding-top:calc(0.75rem+env(safe-area-inset-top))]">
        <div className="mx-auto flex max-w-4xl items-center gap-3">
          <h1 className="min-w-0 flex-1 text-2xl font-black tracking-tight text-slate-950">
            Akun
          </h1>
          <Link
            href="/notifications"
            aria-label="Buka notifikasi"
            className="grid h-11 w-11 place-items-center rounded-full bg-slate-50 text-slate-700 transition active:scale-[0.96]"
          >
            <FiBell className="h-5 w-5" aria-hidden="true" />
          </Link>
          <Link
            href="/account/settings"
            aria-label="Buka pengaturan"
            className="grid h-11 w-11 place-items-center rounded-full bg-slate-50 text-slate-700 transition active:scale-[0.96]"
          >
            <FiSettings className="h-5 w-5" aria-hidden="true" />
          </Link>
        </div>
      </header>

      <div className="mx-auto max-w-4xl space-y-5 px-4 py-5">
        <section className="overflow-hidden rounded-[26px] bg-gradient-to-br from-[#1677FF] via-[#1565D8] to-[#0F4EAF] p-4 text-white shadow-[0_16px_36px_rgba(21,101,216,0.22)]">
          <div className="flex items-start gap-3">
            <AccountProfileAvatar
              userId={user?.id ?? session.sub}
              name={displayName}
              size="md"
            />
            <div className="min-w-0 flex-1">
              <span className="inline-flex rounded-full bg-white/16 px-2.5 py-0.5 text-[11px] font-black text-white ring-1 ring-white/20">
                Member Natalo
              </span>
              <h2 className="mt-1.5 truncate text-xl font-black leading-tight tracking-tight">
                Halo, {displayName}!
              </h2>
              <p className="mt-0.5 text-sm font-semibold leading-5 text-blue-50">
                Senang melihatmu kembali di Natalo
              </p>
            </div>
          </div>

          <div className="mt-4 grid grid-cols-2 gap-2 border-t border-white/18 pt-3">
            <div className="rounded-2xl bg-white/12 px-3 py-2 ring-1 ring-white/16">
              <p className="text-xl font-black leading-none">{points.toLocaleString("id-ID")}</p>
              <p className="mt-1 text-[11px] font-bold text-blue-50">Loyalty Point</p>
            </div>
            <div className="rounded-2xl bg-white/12 px-3 py-2 ring-1 ring-white/16">
              <p className="text-sm font-black leading-tight">{memberSince}</p>
              <p className="mt-1 text-[11px] font-bold text-blue-50">Member sejak</p>
            </div>
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

        <section className="rounded-[22px] border border-slate-100 bg-white p-4 shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
          <div className="flex items-center justify-between gap-3">
            <h2 className="text-lg font-black text-[#101A33]">Pesanan Saya</h2>
            <Link
              href="/member/orders"
              className="inline-flex items-center gap-1 text-sm font-black text-natalo-600"
            >
              Lihat semua
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
          <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
            <TransactionMenuItem href="/member/vouchers" icon={FiTag} title="Voucher" description={voucherSubtitle} />
            <TransactionMenuItem href="/wishlist" icon={FiHeart} title="Wishlist" description="Produk yang kamu favoritkan" />
            <TransactionMenuItem href="/member/reviews" icon={FiStar} title="Review" description="Ulasan dan rating produk" />
            <TransactionMenuItem href="/akun/alamat" icon={FiMapPin} title="Alamat" description="Kelola alamat pengiriman" />
            <TransactionMenuItem href="/account/loyalty/redeem" icon={FiGift} title="Tukar Poin" description="Ubah poin jadi voucher" />
            <TransactionMenuItem href="/member/points" icon={FiShoppingBag} title="Riwayat Poin" description="Transaksi poin member" />
          </div>
        </section>

        <section>
          <h2 className="px-1 text-lg font-black text-[#101A33]">Feed Saya</h2>
          <div className="mt-3 divide-y divide-slate-100 overflow-hidden rounded-[22px] border border-slate-100 bg-white shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
            <FeedListItem
              href="/akun/postingan-saya"
              icon={FiPlayCircle}
              title="Postingan Saya"
              subtitle={
                pendingFeedPostCount > 0
                  ? `${pendingFeedPostCount} postingan menunggu review`
                  : "Kelola video Feed yang kamu upload"
              }
              badgeCount={pendingFeedPostCount}
            />
            <FeedListItem
              href="/feed/upload"
              icon={FiPlus}
              title="+ Upload Video"
              subtitle="Bagikan momen seru hewan peliharaanmu"
              accent
            />
          </div>
        </section>
      </div>
    </main>
  );
}
