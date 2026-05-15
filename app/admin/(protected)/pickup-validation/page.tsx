import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { markAsPickedUp } from "../orders/[id]/actions";

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
      <Link href="/admin/orders" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
        ← Kembali ke pesanan
      </Link>
      <div className="mt-3 md:mt-4">
        <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">Validasi Pickup</h1>
        <p className="mt-1 text-sm text-zinc-500">
          Masukkan kode pickup yang ditunjukkan customer saat mengambil pesanan.
        </p>
      </div>

      <form action="/admin/pickup-validation" className="mt-5 rounded-2xl border border-zinc-200 p-4 md:mt-8 md:rounded-3xl md:p-5">
        <label className="text-sm font-bold text-zinc-700" htmlFor="code">
          Kode Pickup
        </label>
        <div className="mt-2 flex flex-col gap-3 sm:flex-row">
          <input
            id="code"
            name="code"
            defaultValue={code}
            placeholder="NTL-4821"
            className="min-w-0 flex-1 rounded-2xl border border-zinc-300 px-4 py-3 font-mono text-sm font-black uppercase outline-none focus:border-zinc-700"
          />
          <button className="rounded-full bg-zinc-950 px-6 py-3 text-sm font-black text-white hover:bg-zinc-800">
            Cek Kode
          </button>
        </div>
      </form>

      {invalidCode && (
        <div className="mt-5 rounded-3xl border border-red-100 bg-red-50 p-5 text-sm font-semibold text-red-700">
          Kode pickup tidak ditemukan. Pastikan kode yang dimasukkan sudah benar.
        </div>
      )}

      {order && (
        <section className="mt-5 rounded-3xl border border-green-200 bg-green-50 p-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="text-sm font-black text-green-800">Pesanan Valid</p>
              <h2 className="mt-1 text-2xl font-black text-zinc-950">{order.orderNumber}</h2>
              <p className="mt-1 text-sm text-zinc-600">Customer: {order.customerName}</p>
            </div>
            <span className="rounded-full bg-white px-3 py-1 text-xs font-black text-green-700">
              {PICKUP_STATUS_LABELS[order.pickupStatus ?? ""] ?? order.pickupStatus ?? "-"}
            </span>
          </div>

          <div className="mt-5 space-y-3 rounded-2xl bg-white p-4 text-sm">
            <p>
              <span className="font-semibold">Metode:</span> Ambil Sendiri di Toko
            </p>
            <p>
              <span className="font-semibold">Kode:</span>{" "}
              <span className="font-mono font-black">{order.pickupCode}</span>
            </p>
            <p>
              <span className="font-semibold">Total:</span> {formatRupiah(order.total)}
            </p>
            <div>
              <p className="font-semibold">Produk</p>
              <div className="mt-2 space-y-2">
                {order.items.map((item) => (
                  <div key={item.id} className="flex justify-between gap-3 rounded-xl bg-zinc-50 px-3 py-2">
                    <span>{item.name}</span>
                    <span className="font-black">Qty {item.quantity}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {canHandOver && handOverAction ? (
            <form action={handOverAction} className="mt-5">
              <button className="w-full rounded-full bg-emerald-600 px-6 py-3 text-sm font-black text-white hover:bg-emerald-700">
                Serahkan Pesanan
              </button>
            </form>
          ) : (
            <p className="mt-5 rounded-2xl bg-white px-4 py-3 text-sm font-bold text-zinc-600">
              Pesanan belum bisa diserahkan. Pastikan status siap diambil, pembayaran lunas, dan belum pernah diambil.
            </p>
          )}
        </section>
      )}
    </div>
  );
}
