import Link from "next/link";
import { notFound } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { paymentStatusLabel } from "@/lib/order-labels";
import { PrintButton } from "./PrintButton";

function formatDate(date: Date) {
  return new Intl.DateTimeFormat("id-ID", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Asia/Jakarta",
  }).format(date);
}

function formatShippingMethod(order: {
  courierCode: string | null;
  courierService: string | null;
}) {
  const method = [order.courierCode, order.courierService].filter(Boolean).join(" ");
  return method || "-";
}

export default async function PrintOrderPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const order = await prisma.order.findUnique({
    where: { id },
    include: { items: true },
  });

  if (!order) return notFound();

  return (
    <main className="min-h-screen bg-zinc-100 px-4 py-8 text-zinc-950 print:bg-white print:px-0 print:py-0">
      <div className="mx-auto max-w-3xl print:max-w-none">
        <div className="mb-4 flex items-center justify-between gap-3 print:hidden">
          <Link
            href={`/admin/orders/${order.id}`}
            className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
          >
            Kembali ke detail order
          </Link>
          <PrintButton />
        </div>

        <section className="bg-white p-8 shadow-sm print:p-0 print:shadow-none">
          <header className="border-b-2 border-zinc-950 pb-5">
            <p className="text-2xl font-black uppercase tracking-wide">
              Natalo Petshop & Aquarium
            </p>
            <p className="mt-1 text-sm text-zinc-600">Resi / Packing Slip</p>
          </header>

          <div className="mt-6 grid gap-3 text-sm">
            <InfoRow label="Nomor Order" value={order.orderNumber} />
            <InfoRow label="Tanggal" value={formatDate(order.createdAt)} />
            <InfoRow label="Nama Penerima" value={order.customerName} />
            <InfoRow label="No WhatsApp" value={order.customerPhone} />
            <InfoRow
              label="Alamat"
              value={[
                order.shippingAddress,
                order.shippingCity,
                order.shippingPostalCode,
              ]
                .filter(Boolean)
                .join(", ")}
            />
            <InfoRow label="Catatan" value={order.notes || "-"} />
          </div>

          <section className="mt-8">
            <h2 className="text-sm font-black uppercase tracking-wide">Produk</h2>
            <div className="mt-3 overflow-hidden border border-zinc-300">
              <table className="w-full border-collapse text-left text-sm">
                <thead className="bg-zinc-100 print:bg-white">
                  <tr className="border-b border-zinc-300">
                    <th className="px-3 py-2 font-bold">Nama produk</th>
                    <th className="px-3 py-2 font-bold">Varian</th>
                    <th className="px-3 py-2 text-center font-bold">Qty</th>
                    <th className="px-3 py-2 text-right font-bold">Harga</th>
                  </tr>
                </thead>
                <tbody>
                  {order.items.map((item) => (
                    <tr key={item.id} className="border-b border-zinc-200 last:border-b-0">
                      <td className="px-3 py-3 align-top font-semibold">{item.name}</td>
                      <td className="px-3 py-3 align-top text-zinc-700">
                        {item.variantLabel || "-"}
                      </td>
                      <td className="px-3 py-3 text-center align-top">{item.quantity}</td>
                      <td className="px-3 py-3 text-right align-top">
                        {formatRupiah(item.price)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <div className="mt-6 grid gap-3 border-t border-zinc-300 pt-5 text-sm">
            <InfoRow label="Total" value={formatRupiah(order.total)} strong />
            <InfoRow
              label="Status Pembayaran"
              value={paymentStatusLabel(order.paymentStatus)}
            />
            <InfoRow label="Metode Pengiriman" value={formatShippingMethod(order)} />
          </div>
        </section>
      </div>
    </main>
  );
}

function InfoRow({
  label,
  value,
  strong = false,
}: {
  label: string;
  value: string;
  strong?: boolean;
}) {
  return (
    <div className="grid grid-cols-[150px_1fr] gap-3">
      <dt className="font-bold">{label}:</dt>
      <dd className={strong ? "font-black" : "font-medium"}>{value}</dd>
    </div>
  );
}
