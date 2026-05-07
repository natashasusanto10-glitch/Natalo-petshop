import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { LogoutButton } from "@/components/LogoutButton";
import { MemberNav } from "@/components/MemberNav";
import { ClaimVoucherButton } from "@/components/ClaimVoucherButton";
import { ReorderButton } from "@/components/ReorderButton";
import Link from "next/link";

export default async function MemberPage() {
  const session = await getSession();

  const orders = session
    ? await prisma.order.findMany({
        where: { userId: session.sub },
        orderBy: { createdAt: "desc" },
        take: 5,
        include: { items: true },
      })
    : [];

  const totalPoints = session
    ? await prisma.customerPoint.aggregate({
        where: { userId: session.sub },
        _sum: { points: true },
      })
    : null;

  const pointHistory = session
    ? await prisma.customerPoint.findMany({
        where: { userId: session.sub },
        orderBy: { createdAt: "desc" },
        take: 5,
      })
    : [];

  const points = totalPoints?._sum.points ?? 0;

  // ── Last purchased unique items (untuk Reorder Cepat) ─────────
  // Ambil ~30 item terakhir dari order user, lalu dedup by (productId, variantId)
  const recentItemsRaw = session
    ? await prisma.orderItem.findMany({
        where: {
          order: { userId: session.sub },
          product: { isActive: true },
        },
        include: {
          order: { select: { orderNumber: true, createdAt: true } },
          product: { select: { slug: true, imageUrl: true } },
        },
        orderBy: { order: { createdAt: "desc" } },
        take: 30,
      })
    : [];

  const seenKeys = new Set<string>();
  const recentUniqueItems: typeof recentItemsRaw = [];
  for (const item of recentItemsRaw) {
    const key = `${item.productId}:${item.variantId ?? ""}`;
    if (seenKeys.has(key)) continue;
    seenKeys.add(key);
    recentUniqueItems.push(item);
    if (recentUniqueItems.length >= 5) break;
  }

  // ── Birthday voucher check ──────────────────────────────────
  // Anti double-claim: birthdayVoucherYear mencatat tahun voucher sudah dikeluarkan.
  // Berapapun birthDate diubah, user hanya bisa dapat voucher 1x per tahun.
  let birthdayVoucherCode: string | null = null;
  if (session) {
    const user = await prisma.user.findUnique({
      where: { id: session.sub },
      select: { birthDate: true, birthdayVoucherYear: true },
    });
    if (user?.birthDate) {
      const today = new Date();
      const bd = user.birthDate;
      const isBirthday =
        bd.getDate() === today.getDate() && bd.getMonth() === today.getMonth();
      const currentYear = today.getFullYear();
      const alreadyClaimedThisYear = user.birthdayVoucherYear === currentYear;

      if (isBirthday) {
        const code = `BDAY-${session.sub.slice(-6).toUpperCase()}-${currentYear}`;
        if (!alreadyClaimedThisYear) {
          // Pertama kali claim tahun ini — buat voucher & kunci tahunnya
          const expiresAt = new Date(today);
          expiresAt.setDate(expiresAt.getDate() + 7);
          await prisma.$transaction([
            prisma.voucher.upsert({
              where: { code },
              create: {
                code,
                description: `Voucher ulang tahun ${currentYear} 🎂`,
                discountPercent: 15,
                minimumOrder: 0,
                maxUsage: 1,
                expiresAt,
                isActive: true,
                userId: session.sub,
              },
              update: { userId: session.sub },
            }),
            // Kunci: tandai bahwa user sudah dapat voucher tahun ini
            prisma.user.update({
              where: { id: session.sub },
              data: { birthdayVoucherYear: currentYear },
            }),
          ]);
        }
        // Tampilkan banner (baik baru maupun yang sudah ada)
        birthdayVoucherCode = code;
      }
    }
  }

  const STATUS_LABEL: Record<string, string> = {
    PENDING: "Menunggu",
    PAID: "Dibayar",
    PROCESSING: "Diproses",
    SHIPPED: "Dikirim",
    DELIVERED: "Selesai",
    CANCELLED: "Dibatalkan",
  };

  const STATUS_COLOR: Record<string, string> = {
    PENDING: "bg-orange-100 text-orange-600",
    PAID: "bg-blue-100 text-blue-600",
    PROCESSING: "bg-blue-100 text-blue-600",
    SHIPPED: "bg-indigo-100 text-indigo-600",
    DELIVERED: "bg-green-100 text-green-600",
    CANCELLED: "bg-red-100 text-red-500",
  };

  return (
    <div className="mx-auto max-w-4xl px-4 py-10">
      {/* Header member */}
      <div className="overflow-hidden rounded-3xl bg-orange-500 p-8 text-white">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-white/20 text-3xl font-black">
              {session?.name?.charAt(0)?.toUpperCase() ?? "🐾"}
            </div>
            <div>
              <p className="text-sm text-orange-100">Member resmi</p>
              <h1 className="mt-0.5 text-2xl font-black">Halo, {session?.name ?? "Member"}!</h1>
            </div>
          </div>
        )}

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="rounded-2xl border border-natalo-100 bg-natalo-50 p-5">
          <p className="text-sm font-semibold text-natalo-700">Loyalty Poin</p>
          <p className="mt-2 text-3xl font-black text-gray-900">{points}</p>
          <p className="mt-1 text-sm text-gray-500">1 poin setiap Rp20.000 belanja.</p>
          <ClaimVoucherButton totalPoints={points} />
        </div>
        <div className="rounded-2xl border border-gray-100 bg-white p-5">
          <div className="flex items-center justify-between gap-2">
            <p className="text-sm font-semibold text-gray-500">🔄 Reorder Cepat</p>
            {recentUniqueItems.length > 0 && (
              <Link
                href="/member/orders"
                className="text-xs font-bold text-natalo-600 hover:underline"
              >
                Lihat semua →
              </Link>
            )}
          </div>

          {recentUniqueItems.length === 0 ? (
            <>
              <p className="mt-2 font-bold text-gray-900">Belum ada pesanan</p>
              <p className="mt-1 text-sm text-gray-500">
                Item yang sudah pernah kamu beli akan muncul di sini untuk pesanan ulang cepat.
              </p>
            </>
          ) : (
            <div className="mt-3 space-y-2.5">
              {recentUniqueItems.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center gap-2.5 rounded-xl border border-gray-100 p-2 transition hover:border-natalo-200 hover:bg-natalo-50/30"
                >
                  {/* Thumbnail */}
                  <Link
                    href={`/products/${item.product.slug}`}
                    className="h-10 w-10 shrink-0 overflow-hidden rounded-lg bg-gray-100"
                  >
                    {item.product.imageUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={item.product.imageUrl}
                        alt={item.name}
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <div className="flex h-full items-center justify-center text-base">
                        🐾
                      </div>
                    )}
                  </Link>

                  {/* Info */}
                  <div className="min-w-0 flex-1">
                    <Link
                      href={`/products/${item.product.slug}`}
                      className="line-clamp-1 text-xs font-semibold text-gray-900 hover:text-natalo-700"
                    >
                      {item.name}
                    </Link>
                    {item.variantLabel && (
                      <p className="truncate text-[10px] text-natalo-600">
                        {item.variantLabel}
                      </p>
                    )}
                    <p className="text-[10px] text-gray-400">
                      {formatRupiah(item.price)}
                    </p>
                  </div>

                  {/* Reorder button (ghost compact) */}
                  <ReorderButton
                    orderNumber={item.order.orderNumber}
                    itemId={item.id}
                    variant="ghost"
                    className="shrink-0 !px-2.5 !py-1 !text-[11px]"
                  >
                    Beli Lagi
                  </ReorderButton>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Quick navigation */}
      <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { href: "/member/orders", icon: "📦", label: "Pesanan Saya" },
          { href: "/member/profile", icon: "👤", label: "Profil" },
          { href: "/wishlist", icon: "🤍", label: "Wishlist" },
          { href: "/order-status", icon: "🔍", label: "Cek Status" },
        ].map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="flex flex-col items-center gap-2 rounded-2xl border border-gray-100 bg-white p-4 text-center shadow-sm transition hover:border-orange-200 hover:shadow-md"
          >
            <span className="text-2xl">{item.icon}</span>
            <span className="text-xs font-semibold text-gray-700">{item.label}</span>
          </Link>
        ))}
      </div>

      {/* Benefit cards */}
      <div className="mt-6 grid gap-4 sm:grid-cols-3">
        <div className="rounded-2xl border border-orange-100 bg-orange-50 p-5">
          <span className="text-2xl">🎟️</span>
          <p className="mt-2 font-bold text-gray-900">Voucher Member</p>
          <p className="mt-1 text-sm text-gray-500">Gunakan kode <span className="font-mono font-bold text-orange-600">MEMBER10</span> untuk diskon 10%.</p>
        </div>
        <div className="rounded-2xl border border-gray-100 bg-gray-50 p-5">
          <span className="text-2xl">⚡</span>
          <p className="mt-2 font-bold text-gray-900">Reorder Cepat</p>
          <p className="mt-1 text-sm text-gray-500">Beli ulang dari riwayat pesanan dengan sekali klik.</p>
        </div>
        <div className="rounded-2xl border border-gray-100 bg-gray-50 p-5">
          <span className="text-2xl">🔔</span>
          <p className="mt-2 font-bold text-gray-900">Notifikasi Order</p>
          <p className="mt-1 text-sm text-gray-500">Aktifkan push notification di halaman cek status pesanan.</p>
        </div>
      </div>

      {/* Order history */}
      <section className="mt-8">
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-black text-gray-900">Pesanan Terbaru</h2>
          <Link href="/member/orders" className="text-sm font-semibold text-orange-500 hover:underline">
            Lihat semua →
          </Link>
        </div>

        <div className="mt-4 space-y-3">
          {orders.length > 0 ? (
            orders.map((order) => (
              <div key={order.id} className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <p className="font-bold text-gray-900">{order.orderNumber}</p>
                    <p className="mt-0.5 text-sm text-gray-400">
                      {order.items.length} produk · {formatRupiah(order.total)}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className={`rounded-full px-3 py-1 text-xs font-semibold ${STATUS_COLOR[order.status] ?? "bg-gray-100 text-gray-500"}`}>
                      {STATUS_LABEL[order.status] ?? order.status}
                    </span>
                    <Link
                      href={`/order-status?order=${order.orderNumber}`}
                      className="text-sm font-semibold text-natalo-600 hover:underline"
                    >
                      Detail
                    </Link>
                  </div>
                </div>
              </div>
            ))
          ) : (
            <div className="rounded-2xl border border-gray-100 bg-gray-50 p-8 text-center">
              <p className="text-sm text-gray-500">Belum ada pesanan.</p>
              <Link
                href="/products"
                className="mt-4 inline-flex rounded-full bg-natalo-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-natalo-700"
              >
                Mulai belanja
              </Link>
            </div>
          )}
        </div>
      </section>
      </main>
    </div>
  );
}
