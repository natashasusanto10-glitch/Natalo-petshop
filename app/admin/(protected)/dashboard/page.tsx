import { prisma } from "@/lib/prisma";
import { formatRupiah, jakartaTodayRange, jakartaDayRange } from "@/lib/format";
import { getSession } from "@/lib/auth";
import {
  buildDashboardRevenue,
  type RevenueBucket,
} from "@/lib/admin/dashboard-revenue";
import { DashboardView } from "@/components/admin/views/DashboardView";
// Ambang menipis + filter stok dibagi dengan halaman /admin/stock supaya dua
// tempat tidak pernah memberi angka berbeda untuk produk yang sama.
import { LOW_STOCK_LIMIT, productStockWhere } from "@/lib/admin/stock-filters";

/** Simple greeting based on Jakarta hour. */
function getGreeting() {
  const hour = new Date().toLocaleString("en-US", {
    timeZone: "Asia/Jakarta",
    hour: "2-digit",
    hour12: false,
  });
  const h = parseInt(hour, 10);
  if (h < 11) return "Selamat pagi";
  if (h < 15) return "Selamat siang";
  if (h < 19) return "Selamat sore";
  return "Selamat malam";
}

const ICONS = {
  newOrder:
    "M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 3h6v4H9z",
  wallet:
    "M21 12V7H5a2 2 0 0 1 0-4h14v4M3 5v14a2 2 0 0 0 2 2h16v-5M18 12a2 2 0 0 0 0 4h4v-4Z",
  check: "M20 6 9 17l-5-5",
  truck:
    "M3 5h11v12H3zM14 9h4l3 4v4h-7M7 16a2 2 0 1 0 0 4a2 2 0 1 0 0-4M18 16a2 2 0 1 0 0 4a2 2 0 1 0 0-4",
  sales: "M3 3v18h18M7 15l4-4 3 3 5-5",
  stock: "M3 7l9-4 9 4v10l-9 4-9-4V7Zm0 0 9 4 9-4M12 11v10M7 5l9 4",
  alert: "M12 9v4M12 17h.01M3 12 12 3l9 9-9 9-9-9Z",
  variant: "M3 7h18M3 12h18M3 17h12",
  voucher:
    "M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82zM7 7h.01",
  clock: "M12 6v6l4 2M3 12a9 9 0 1 0 18 0 9 9 0 0 0-18 0z",
};

export default async function AdminDashboardPage() {
  const session = await getSession("ADMIN");
  const now = new Date();
  const { start: todayStart, end: todayEnd } = jakartaTodayRange(now);
  const revenueStart = jakartaDayRange(13, now).start;
  const expiringSoonCutoff = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  const usableVoucherWhere = {
    isActive: true,
    startsAt: { lte: now },
    OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
    AND: [
      {
        OR: [
          { maxUsage: null },
          { usedCount: { lt: prisma.voucher.fields.maxUsage } },
        ],
      },
    ],
  };

  const [
    orderStatusCounts,
    waitingPaymentCount,
    paidUnshippedCount,
    actionOrders,
    lowStockCount,
    outOfStockCount,
    lowStockProducts,
    outOfStockProducts,
    outOfStockVariantCount,
    outOfStockVariants,
    voucherActiveCount,
    voucherExpiringCount,
    expiringVouchers,
    todayOrderCount,
    verificationCount,
    pickupCount,
    revenueBuckets,
  ] = await Promise.all([
    prisma.order.groupBy({ by: ["status"], _count: true }),
    prisma.order.count({
      where: {
        paymentStatus: { in: ["UNPAID", "PENDING"] },
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
    }),
    prisma.order.count({
      where: {
        paymentStatus: "PAID",
        status: { in: ["PENDING", "PAID", "PROCESSING"] },
      },
    }),
    prisma.order.findMany({
      orderBy: { createdAt: "desc" },
      take: 4,
      include: { items: { select: { quantity: true } } },
    }),
    // `productStockWhere` membatasi hasVariants:false. Tanpa itu, stok induk
    // produk bervarian yang memang selalu 0 membuat SETIAP produk bervarian
    // terhitung habis — kartu "Stok Habis" melapor alarm palsu, dan varian
    // yang benar-benar habis sudah dihitung terpisah di bawah.
    prisma.product.count({ where: productStockWhere("menipis") }),
    prisma.product.count({ where: productStockWhere("habis") }),
    prisma.product.findMany({
      where: productStockWhere("menipis"),
      orderBy: { stock: "asc" },
      take: 8,
      select: { id: true, name: true, stock: true, price: true },
    }),
    prisma.product.findMany({
      where: productStockWhere("habis"),
      orderBy: { updatedAt: "desc" },
      take: 8,
      select: { id: true, name: true, stock: true, price: true },
    }),
    prisma.productVariant.count({
      where: {
        isActive: true,
        deletedAt: null,
        stock: 0,
        product: { isActive: true },
      },
    }),
    prisma.productVariant.findMany({
      where: {
        isActive: true,
        deletedAt: null,
        stock: 0,
        product: { isActive: true },
      },
      orderBy: { updatedAt: "desc" },
      take: 8,
      select: {
        id: true,
        sku: true,
        product: { select: { id: true, name: true } },
        options: { select: { option: { select: { value: true } } } },
      },
    }),
    prisma.voucher.count({
      where: usableVoucherWhere,
    }),
    prisma.voucher.count({
      where: {
        ...usableVoucherWhere,
        expiresAt: { gt: now, lte: expiringSoonCutoff },
      },
    }),
    prisma.voucher.findMany({
      where: {
        ...usableVoucherWhere,
        expiresAt: { gt: now, lte: expiringSoonCutoff },
      },
      orderBy: { expiresAt: "asc" },
      take: 5,
      select: {
        id: true,
        code: true,
        expiresAt: true,
        usedCount: true,
        maxUsage: true,
      },
    }),
    prisma.order.count({
      where: { createdAt: { gte: todayStart, lte: todayEnd } },
    }),
    prisma.order.count({
      where: {
        paymentProofStatus: "PENDING_REVIEW",
        paymentStatus: { in: ["UNPAID", "PENDING"] },
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
    }),
    prisma.order.count({
      where: {
        orderType: "SELF_PICKUP",
        status: "READY_FOR_PICKUP",
        paymentStatus: "PAID",
      },
    }),
    // Database aggregation returns hourly totals only, never individual order data.
    // Prisma DateTime columns are UTC timestamps without time zone.
    prisma.$queryRaw<RevenueBucket[]>`
      SELECT to_char(("createdAt" AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YYYY-MM-DD') AS day,
        extract(hour FROM ("createdAt" AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Jakarta')::int AS hour,
        sum(total)::float8 AS total
      FROM "Order"
      WHERE "createdAt" >= ${revenueStart} AND "createdAt" <= ${now}
        AND "paymentStatus" = 'PAID' AND status NOT IN ('CANCELLED', 'REFUNDED')
      GROUP BY 1, 2 ORDER BY 1, 2
    `,
  ]);

  const revenue = buildDashboardRevenue(revenueBuckets, now);
  const countMap: Record<string, number> = {};
  for (const row of orderStatusCounts) countMap[row.status] = row._count;

  // Stat tiles — variant assigned by semantic urgency:
  //   warning = perlu action admin
  //   danger  = stok / abuse — urgent
  //   success = state oke / sales positif
  //   primary = info netral important
  //   accent  = highlight (sales hari ini — feature angka utama)
  const stats: Array<{
    label: string;
    value: string | number;
    helper: string;
    href: string;
    variant:
      | "default"
      | "primary"
      | "success"
      | "warning"
      | "danger"
      | "accent";
    iconPath: string;
  }> = [
    {
      label: "Penjualan hari ini",
      value: formatRupiah(revenue.todayTotal),
      helper: "Order lunas hari ini",
      href: "/admin/orders?date=TODAY&pay=PAID",
      variant: "accent",
      iconPath: ICONS.sales,
    },
    {
      label: "Order Baru",
      value: countMap.PENDING ?? 0,
      helper: "Belum diproses",
      href: "/admin/orders?status=PENDING",
      variant: "warning",
      iconPath: ICONS.newOrder,
    },
    {
      label: "Menunggu Pembayaran",
      value: waitingPaymentCount,
      helper: "Belum lunas / verifikasi",
      href: "/admin/orders?pay=WAITING",
      variant: "warning",
      iconPath: ICONS.wallet,
    },
    {
      label: "Sudah Dibayar",
      value: countMap.PAID ?? 0,
      helper: "Siap mulai packing",
      href: "/admin/orders?status=PAID",
      variant: "success",
      iconPath: ICONS.check,
    },
    {
      label: "Diproses",
      value: countMap.PROCESSING ?? 0,
      helper: "Perlu packing",
      href: "/admin/orders?status=PROCESSING",
      variant: "primary",
      iconPath: ICONS.newOrder,
    },
    {
      label: "Dikirim",
      value: countMap.SHIPPED ?? 0,
      helper: "Dalam pengiriman",
      href: "/admin/orders?status=SHIPPED",
      variant: "primary",
      iconPath: ICONS.truck,
    },
    {
      label: "Selesai",
      value: countMap.DELIVERED ?? 0,
      helper: "Order selesai",
      href: "/admin/orders?status=DELIVERED",
      variant: "success",
      iconPath: ICONS.check,
    },
    {
      label: "Produk Stok Menipis",
      value: lowStockCount,
      helper: `Stok 1-${LOW_STOCK_LIMIT}`,
      href: "/admin/stock?filter=menipis",
      variant: "warning",
      iconPath: ICONS.stock,
    },
    {
      label: "Produk Habis",
      value: outOfStockCount,
      helper: "Stok 0",
      href: "/admin/stock?filter=habis",
      variant: "danger",
      iconPath: ICONS.alert,
    },
    {
      label: "Varian Habis",
      value: outOfStockVariantCount,
      helper: "Varian aktif stok 0",
      href: "/admin/stock",
      variant: "danger",
      iconPath: ICONS.variant,
    },
    {
      label: "Voucher Aktif",
      value: voucherActiveCount,
      helper: "Berlaku saat ini",
      href: "/admin/vouchers",
      variant: "primary",
      iconPath: ICONS.voucher,
    },
    {
      label: "Voucher segera berakhir",
      value: voucherExpiringCount,
      helper: "Habis dalam 7 hari",
      href: "/admin/vouchers",
      variant: "warning",
      iconPath: ICONS.clock,
    },
  ];

  return (
    <DashboardView
      greeting={getGreeting()}
      adminName={session?.name ?? "Admin"}
      now={now}
      paidUnshippedCount={paidUnshippedCount}
      stats={[
        {
          ...stats[0],
          value: formatRupiah(revenue.todayTotal),
          helper:
            revenue.yesterdayTotal > 0
              ? "dibanding total kemarin"
              : "Pesanan lunas hari ini (WIB)",
          trend:
            revenue.yesterdayTotal > 0
              ? {
                  value:
                    Math.round(
                      ((revenue.todayTotal - revenue.yesterdayTotal) /
                        revenue.yesterdayTotal) *
                        1000
                    ) / 10,
                }
              : undefined,
        },
        {
          label: "Pesanan hari ini",
          value: todayOrderCount,
          helper: "Pesanan yang masuk hari ini (WIB)",
          href: "/admin/orders?date=TODAY",
          variant: "default",
          iconPath: ICONS.newOrder,
        },
        {
          label: "Perlu dikemas",
          value: paidUnshippedCount,
          helper: "Pembayaran sudah terverifikasi",
          href: "/admin/orders?status=NEED_PACKING",
          variant: "default",
          iconPath: ICONS.stock,
        },
        {
          ...stats[7],
          label: "Stok menipis",
          variant: "default",
          iconPath: ICONS.alert,
        },
        ...stats.slice(1, 7),
        ...stats.slice(8),
      ]}
      verificationCount={verificationCount}
      pickupCount={pickupCount}
      revenue={revenue}
      actionOrders={actionOrders}
      lowStockProducts={lowStockProducts}
      outOfStockProducts={outOfStockProducts}
      outOfStockVariants={outOfStockVariants}
      expiringVouchers={expiringVouchers}
    />
  );
}
