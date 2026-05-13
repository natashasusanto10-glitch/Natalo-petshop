import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { ReorderButton } from "@/components/ReorderButton";
import { requireCustomerSession } from "@/lib/session-guards";

type OrderGroup = "all" | "unpaid" | "processing" | "shipped" | "completed" | "cancelled";

const STATUS_TABS: { key: OrderGroup; label: string }[] = [
  { key: "all", label: "Semua" },
  { key: "unpaid", label: "Belum Bayar" },
  { key: "processing", label: "Diproses" },
  { key: "shipped", label: "Dikirim" },
  { key: "completed", label: "Selesai" },
  { key: "cancelled", label: "Dibatalkan" },
];

const STATUS_COLOR: Record<OrderGroup, string> = {
  all: "bg-zinc-100 text-zinc-600",
  unpaid: "bg-amber-100 text-amber-700",
  processing: "bg-blue-100 text-blue-700",
  shipped: "bg-indigo-100 text-indigo-700",
  completed: "bg-green-100 text-green-700",
  cancelled: "bg-red-100 text-red-600",
};

const GROUP_LABEL: Record<OrderGroup, string> = {
  all: "Semua",
  unpaid: "Belum Bayar",
  processing: "Diproses",
  shipped: "Dikirim",
  completed: "Selesai",
  cancelled: "Dibatalkan",
};

function asOrderGroup(value: string | undefined): OrderGroup {
  return STATUS_TABS.some((tab) => tab.key === value) ? (value as OrderGroup) : "all";
}

function getOrderGroup(order: { status: string; paymentStatus: string }): Exclude<OrderGroup, "all"> {
  if (
    order.status === "CANCELLED" ||
    order.status === "REFUNDED" ||
    order.paymentStatus === "FAILED" ||
    order.paymentStatus === "EXPIRED" ||
    order.paymentStatus === "REFUNDED"
  ) {
    return "cancelled";
  }

  if (order.status === "DELIVERED") return "completed";
  if (order.status === "SHIPPED") return "shipped";

  if (order.paymentStatus === "PAID" || order.status === "PAID" || order.status === "PROCESSING") {
    return "processing";
  }

  return "unpaid";
}

function formatDate(date: Date) {
  return new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(date);
}

function buildWhatsAppUrl(message: string) {
  const phone =
    process.env.NEXT_PUBLIC_WA_NUMBER ||
    process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ||
    "6281289997113";
  return `https://wa.me/${phone.replace(/^\+/, "")}?text=${encodeURIComponent(message)}`;
}

function BackIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2.2}
      className="h-5 w-5"
      aria-hidden
    >
      <path d="M15 18l-6-6 6-6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export default async function MemberOrdersPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const [{ status }, session] = await Promise.all([searchParams, requireCustomerSession()]);
  const activeStatus = asOrderGroup(status);

  const orders = await prisma.order.findMany({
    where: { userId: session.sub },
    orderBy: { createdAt: "desc" },
    include: {
      items: {
        select: { name: true, quantity: true, price: true, productId: true },
      },
    },
  });

  const visibleOrders =
    activeStatus === "all"
      ? orders
      : orders.filter((order) => getOrderGroup(order) === activeStatus);

  return (
    <main className="min-h-screen bg-zinc-50 pb-[calc(2rem+env(safe-area-inset-bottom))]">
      <header className="sticky top-0 z-50 border-b border-zinc-100 bg-white px-4 pb-3 pt-3 shadow-sm [padding-top:calc(0.75rem+env(safe-area-inset-top))]">
        <div className="mx-auto flex max-w-4xl items-center gap-2">
          <Link
            href="/member"
            aria-label="Kembali ke akun"
            className="-ml-2 flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-zinc-800 active:bg-zinc-100"
          >
            <BackIcon />
          </Link>
          <h1 className="text-xl font-black text-zinc-950 md:text-2xl">Riwayat Pesanan</h1>
        </div>
      </header>

      <div className="mx-auto max-w-4xl px-4 py-4 md:py-8">
        <nav className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {STATUS_TABS.map((tab) => {
            const active = tab.key === activeStatus;
            const href = tab.key === "all" ? "/member/orders" : `/member/orders?status=${tab.key}`;
            return (
              <Link
                key={tab.key}
                href={href}
                aria-current={active ? "page" : undefined}
                className={`shrink-0 rounded-full border px-4 py-2 text-sm font-bold transition ${
                  active
                    ? "border-blue-500 bg-blue-500 text-white"
                    : "border-zinc-200 bg-white text-zinc-600 active:bg-zinc-50"
                }`}
              >
                {tab.label}
              </Link>
            );
          })}
        </nav>

        <div className="mt-3 space-y-4">
          {visibleOrders.length > 0 ? (
            visibleOrders.map((order) => {
              const group = getOrderGroup(order);
              const detailHref = `/pesanan/${order.orderNumber}`;
              const payHref = order.paymentUrl || detailHref;
              const cancelHref = buildWhatsAppUrl(
                `Halo Natalo, saya ingin membatalkan pesanan ${order.orderNumber}.`,
              );
              const chatHref = buildWhatsAppUrl(
                `Halo Natalo, saya ingin tanya status pesanan ${order.orderNumber}.`,
              );
              const trackingHref = order.biteshipTrackingUrl || detailHref;

              return (
                <article
                  key={order.id}
                  className="rounded-2xl border border-zinc-100 bg-white p-4 shadow-sm md:p-5"
                >
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="font-bold text-zinc-950">{order.orderNumber}</p>
                      <p className="mt-0.5 text-sm text-zinc-400">{formatDate(order.createdAt)}</p>
                    </div>
                    <span className={`rounded-full px-3 py-1 text-xs font-bold ${STATUS_COLOR[group]}`}>
                      Status: {GROUP_LABEL[group]}
                    </span>
                  </div>

                  <div className="mt-4 space-y-2">
                    {order.items.map((item, i) => (
                      <div
                        key={`${order.id}-${item.productId}-${i}`}
                        className="flex justify-between gap-3 text-sm text-zinc-600"
                      >
                        <span className="min-w-0">
                          {item.name} x {item.quantity}
                        </span>
                        <span className="shrink-0 font-semibold text-zinc-700">
                          {formatRupiah(item.price * item.quantity)}
                        </span>
                      </div>
                    ))}
                  </div>

                  <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-zinc-100 pt-4">
                    <span className="text-sm font-black text-zinc-950">
                      Total: {formatRupiah(order.total)}
                    </span>

                    <div className="flex flex-wrap items-center justify-end gap-2">
                      {group === "unpaid" && (
                        <>
                          <a
                            href={payHref}
                            className="rounded-full bg-blue-600 px-4 py-2 text-xs font-black text-white transition hover:bg-blue-700"
                          >
                            Bayar Sekarang
                          </a>
                          <a
                            href={cancelHref}
                            target="_blank"
                            rel="noreferrer"
                            className="rounded-full border border-zinc-200 px-4 py-2 text-xs font-bold text-zinc-700 transition hover:border-red-200 hover:text-red-600"
                          >
                            Batalkan Pesanan
                          </a>
                        </>
                      )}

                      {group === "processing" && (
                        <>
                          <Link
                            href={detailHref}
                            className="rounded-full bg-blue-600 px-4 py-2 text-xs font-black text-white transition hover:bg-blue-700"
                          >
                            Lihat Detail
                          </Link>
                          <a
                            href={chatHref}
                            target="_blank"
                            rel="noreferrer"
                            className="rounded-full border border-zinc-200 px-4 py-2 text-xs font-bold text-zinc-700 transition hover:border-blue-300 hover:text-blue-600"
                          >
                            Chat Admin
                          </a>
                        </>
                      )}

                      {group === "shipped" && (
                        <>
                          <a
                            href={trackingHref}
                            target={order.biteshipTrackingUrl ? "_blank" : undefined}
                            rel={order.biteshipTrackingUrl ? "noreferrer" : undefined}
                            className="rounded-full bg-blue-600 px-4 py-2 text-xs font-black text-white transition hover:bg-blue-700"
                          >
                            Lacak Pesanan
                          </a>
                          <Link
                            href={detailHref}
                            className="rounded-full border border-zinc-200 px-4 py-2 text-xs font-bold text-zinc-700 transition hover:border-blue-300 hover:text-blue-600"
                          >
                            Detail
                          </Link>
                        </>
                      )}

                      {(group === "completed" || group === "cancelled") && (
                        <>
                          <ReorderButton orderId={order.id} className="bg-white" />
                          <Link
                            href={detailHref}
                            className="rounded-full border border-zinc-200 px-4 py-2 text-xs font-bold text-zinc-700 transition hover:border-blue-300 hover:text-blue-600"
                          >
                            Detail
                          </Link>
                        </>
                      )}
                    </div>
                  </div>
                </article>
              );
            })
          ) : (
            <div className="rounded-2xl border border-zinc-100 bg-white p-10 text-center shadow-sm">
              <p className="font-bold text-zinc-700">
                {activeStatus === "all"
                  ? "Belum ada pesanan."
                  : `Belum ada pesanan ${GROUP_LABEL[activeStatus].toLowerCase()}.`}
              </p>
              <Link
                href="/products"
                className="mt-4 inline-flex rounded-full bg-blue-500 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-600"
              >
                Mulai belanja
              </Link>
            </div>
          )}
        </div>
      </div>
    </main>
  );
}
