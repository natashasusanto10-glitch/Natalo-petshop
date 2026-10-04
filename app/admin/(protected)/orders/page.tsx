import { prisma } from "@/lib/prisma";
import { orderSearchWhere } from "@/lib/admin-search";
import { parsePageParam } from "@/lib/admin/pagination";
import { jakartaTodayRange } from "@/lib/format";
import { OrdersView } from "@/components/admin/views/OrdersView";
const PAGE_SIZE = 20;

export default async function AdminOrdersPage({
  searchParams,
}: {
  searchParams: Promise<{
    status?: string;
    pay?: string;
    type?: string;
    page?: string;
    q?: string;
    proof?: string;
    date?: string;
  }>;
}) {
  const {
    status,
    pay,
    type,
    page: pageStr,
    q,
    proof,
    date,
  } = await searchParams;
  const page = parsePageParam(pageStr);
  const search = q?.trim() ?? "";

  const where: Record<string, unknown> = {};
  if (status === "NEED_PACKING") {
    where.status = { in: ["PENDING", "PAID", "PROCESSING"] };
    where.paymentStatus = "PAID";
  } else if (status && status !== "ALL") {
    where.status = status;
  }

  if (type === "SELF_PICKUP") {
    where.orderType = "SELF_PICKUP";
  } else if (type === "DELIVERY") {
    where.orderType = "DELIVERY";
  }

  if (status === "NEED_PACKING") {
    // Filter khusus ini sudah mendefinisikan status dan pembayaran.
  } else if (pay === "WAITING") {
    where.paymentStatus = { in: ["UNPAID", "PENDING"] };
  } else if (pay && pay !== "ALL") {
    where.paymentStatus = pay;
  }

  if (proof === "PENDING_REVIEW") {
    where.AND = [
      {
        paymentProofStatus: "PENDING_REVIEW",
        paymentStatus: { in: ["UNPAID", "PENDING"] },
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
    ];
  }

  if (date === "TODAY") {
    const { start, end } = jakartaTodayRange();
    where.createdAt = { gte: start, lte: end };
    if (pay === "PAID") {
      const existing = Array.isArray(where.AND) ? where.AND : [];
      where.AND = [
        ...existing,
        { status: { notIn: ["CANCELLED", "REFUNDED"] } },
      ];
    }
  }

  // Nomor pesanan / nama pembeli / nomor HP — daftar field-nya dibagi dengan
  // /api/admin/orders lewat lib/admin-search supaya halaman dan API tidak
  // pernah memberi hasil berbeda untuk kata kunci yang sama.
  // Masuk ke AND, bukan OR, supaya pencarian MEMPERSEMPIT filter status yang
  // aktif — bukan menembusnya.
  const searchWhere = orderSearchWhere(search);
  if (searchWhere) {
    // Digabung, bukan ditimpa. Hari ini tak ada filter lain yang memakai AND,
    // tapi menulis `where.AND = ...` menaruh ranjau: filter baru di atas yang
    // kebetulan juga memakai AND (mis. rentang tanggal) akan saling menghapus
    // diam-diam, dan `Record<string, unknown>` tidak akan mengeluh.
    const existing = Array.isArray(where.AND) ? where.AND : [];
    where.AND = [...existing, ...searchWhere.AND];
  }

  const [
    orders,
    total,
    statusCounts,
    needPackingCount,
    verificationCount,
    pickupCount,
  ] = await Promise.all([
    prisma.order.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
      include: {
        items: {
          select: { quantity: true, product: { select: { imageUrl: true } } },
        },
      },
    }),
    prisma.order.count({ where }),
    prisma.order.groupBy({ by: ["status"], _count: true }),
    prisma.order.count({
      where: {
        paymentStatus: "PAID",
        status: { in: ["PENDING", "PAID", "PROCESSING"] },
      },
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
  ]);

  const totalPages = Math.ceil(total / PAGE_SIZE);
  const countMap: Record<string, number> = {};
  for (const s of statusCounts) countMap[s.status] = s._count;
  const totalCount = Object.values(countMap).reduce((a, b) => a + b, 0);

  function buildUrl(overrides: Record<string, string>) {
    const sp = new URLSearchParams();
    const merged: Record<string, string> = {
      status: status || "ALL",
      pay: pay || "ALL",
      type: type || "ALL",
      page: "1",
      q: search,
      proof: proof === "PENDING_REVIEW" ? proof : "",
      date: date === "TODAY" ? date : "",
      ...overrides,
    };
    if (merged.status && merged.status !== "ALL")
      sp.set("status", merged.status);
    if (merged.pay && merged.pay !== "ALL") sp.set("pay", merged.pay);
    if (merged.type && merged.type !== "ALL") sp.set("type", merged.type);
    if (merged.page && merged.page !== "1") sp.set("page", merged.page);
    // Pencarian ikut terbawa saat admin ganti tab — kalau tidak, mengklik
    // "Sudah Dibayar" diam-diam membuang kata kunci yang baru diketik.
    if (merged.q) sp.set("q", merged.q);
    if (merged.date) sp.set("date", merged.date);
    if (merged.proof && !overrides.status && !overrides.pay && !overrides.type)
      sp.set("proof", merged.proof);
    const str = sp.toString();
    return `/admin/orders${str ? `?${str}` : ""}`;
  }

  const tabs = [
    { key: "ALL", label: "Semua", count: totalCount },
    { key: "NEED_PACKING", label: "Siap packing", count: needPackingCount },
    { key: "PENDING", label: "Order Baru", count: countMap["PENDING"] ?? 0 },
    { key: "PAID", label: "Sudah Dibayar", count: countMap["PAID"] ?? 0 },
    {
      key: "PROCESSING",
      label: "Diproses",
      count: countMap["PROCESSING"] ?? 0,
    },
    {
      key: "READY_FOR_PICKUP",
      label: "Siap Diambil",
      count: countMap["READY_FOR_PICKUP"] ?? 0,
    },
    { key: "SHIPPED", label: "Dikirim", count: countMap["SHIPPED"] ?? 0 },
    { key: "DELIVERED", label: "Selesai", count: countMap["DELIVERED"] ?? 0 },
    {
      key: "CANCELLED",
      label: "Dibatalkan",
      count: countMap["CANCELLED"] ?? 0,
    },
    { key: "REFUNDED", label: "Refund", count: countMap["REFUNDED"] ?? 0 },
  ];

  const activeStatus = status || "ALL";
  const activePay = pay || "ALL";
  const activeType = type || "ALL";

  return (
    <OrdersView
      workflowCounts={{
        verification: verificationCount,
        packing: needPackingCount,
        pickup: pickupCount,
        total: totalCount,
      }}
      orders={orders}
      pendingProofReview={proof === "PENDING_REVIEW"}
      todayOnly={date === "TODAY"}
      total={total}
      search={search}
      page={page}
      totalPages={totalPages}
      tabs={tabs}
      activeStatus={activeStatus}
      activePay={activePay}
      activeType={activeType}
      buildUrl={buildUrl}
    />
  );
}
