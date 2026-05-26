import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { markAsPickedUp } from "../orders/[id]/actions";
import { PageHeader, Badge } from "@/components/admin/ui";

const PICKUP_STATUS_LABELS: Record<string, string> = {
  WAITING_PAYMENT: "Menunggu pembayaran",
  PREPARING: "Perlu disiapkan",
  READY: "Siap diambil",
  PICKED_UP: "Sudah diambil",
};

export default async function PickupValidationPage({
  searchParams,
}: {
  searchParams: Promise<{ code?: string }>;
}) {
  const { code: rawCode } = await searchParams;
  const code = rawCode?.trim().toUpperCase() ?? "";
  const order = code
    ? await prisma.order.findUnique({
        where: { pickupCode: code },
        include: { items: true },
      })
    : null;
  const invalidCode = Boolean(code && !order);
  const canHandOver =
    order?.orderType === "SELF_PICKUP" &&
    order.paymentStatus === "PAID" &&
    order.status === "READY_FOR_PICKUP" &&
    order.pickupStatus !== "PICKED_UP";
  const handOverAction = order ? markAsPickedUp.bind(null, order.id) : null;

  return (
    <div className="mx-auto max-w-3xl px-4 py-5 md:py-10">
      <PageHeader
        title="🏪 Validasi Pickup"
        subtitle="Masukkan kode pickup yang ditunjukkan customer saat mengambil pesanan di toko."
        actions={
          <Link
            href="/admin/orders"
            className="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-3.5 py-2 text-xs font-bold text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-50"
          >
            ← Kembali ke pesanan
          </Link>
        }
      />

      <form
        action="/admin/pickup-validation"
        className="mt-6 rounded-2xl border border-zinc-200 bg-white p-4 md:p-5"
      >
        <label
          className="text-sm font-bold text-zinc-700"
          htmlFor="code"
        >
          Kode Pickup
        </label>
        <div className="mt-2 flex flex-col gap-3 sm:flex-row">
          <input
            id="code"
            name="code"
            defaultValue={code}
            placeholder="NTL-4821"
            className="min-w-0 flex-1 rounded-2xl border border-zinc-300 px-4 py-3 font-mono text-base font-black uppercase tracking-wider outline-none transition focus:border-natalo-500 focus:ring-2 focus:ring-natalo-100"
          />
          <button className="rounded-full bg-natalo-600 px-6 py-3 text-sm font-black text-white shadow-sm transition hover:bg-natalo-700">
            Cek Kode
          </button>
        </div>
      </form>

      {invalidCode && (
        <div className="mt-5 flex items-start gap-3 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm font-semibold text-red-700">
          <span className="text-xl leading-none">⚠️</span>
          <p>
            Kode pickup <span className="font-mono font-black">{code}</span> tidak
            ditemukan. Pastikan kode yang dimasukkan sudah benar.
          </p>
        </div>
      )}

      {order && (
        <section className="mt-5 overflow-hidden rounded-2xl border border-emerald-200 bg-gradient-to-br from-emerald-50 via-emerald-50 to-white p-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="inline-flex items-center gap-1.5 rounded-full bg-emerald-500 px-3 py-1 text-xs font-black text-white shadow-sm">
                ✓ Pesanan Valid
              </p>
              <h2 className="mt-2.5 text-2xl font-black text-zinc-950">
                {order.orderNumber}
              </h2>
              <p className="mt-1 text-sm text-zinc-600">
                Customer: <span className="font-bold">{order.customerName}</span>
              </p>
            </div>
            <Badge variant="success" size="md">
              {PICKUP_STATUS_LABELS[order.pickupStatus ?? ""] ??
                order.pickupStatus ??
                "-"}
            </Badge>
          </div>

          <div className="mt-5 space-y-3 rounded-2xl bg-white p-4 text-sm">
            <div className="flex justify-between gap-2 border-b border-zinc-100 pb-2">
              <span className="font-bold text-zinc-700">Metode</span>
              <span className="text-zinc-900">Ambil Sendiri di Toko</span>
            </div>
            <div className="flex justify-between gap-2 border-b border-zinc-100 pb-2">
              <span className="font-bold text-zinc-700">Kode Pickup</span>
              <span className="font-mono font-black tracking-wider text-zinc-950">
                {order.pickupCode}
              </span>
            </div>
            <div className="flex justify-between gap-2 border-b border-zinc-100 pb-2">
              <span className="font-bold text-zinc-700">Total</span>
              <span className="font-black text-zinc-950">
                {formatRupiah(order.total)}
              </span>
            </div>
            <div>
              <p className="font-bold text-zinc-700">Produk</p>
              <div className="mt-2 space-y-2">
                {order.items.map((item) => (
                  <div
                    key={item.id}
                    className="flex items-center justify-between gap-3 rounded-xl bg-zinc-50 px-3 py-2.5"
                  >
                    <span className="truncate font-medium text-zinc-800">
                      {item.name}
                    </span>
                    <Badge variant="info">Qty {item.quantity}</Badge>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {canHandOver && handOverAction ? (
            <form action={handOverAction} className="mt-5">
              <button className="w-full rounded-full bg-emerald-600 px-6 py-3.5 text-sm font-black text-white shadow-sm transition hover:bg-emerald-700">
                ✓ Serahkan Pesanan ke Customer
              </button>
            </form>
          ) : (
            <p className="mt-5 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-semibold text-amber-800">
              ⚠️ Pesanan belum bisa diserahkan. Pastikan status siap diambil,
              pembayaran lunas, dan belum pernah diambil.
            </p>
          )}
        </section>
      )}
    </div>
  );
}
