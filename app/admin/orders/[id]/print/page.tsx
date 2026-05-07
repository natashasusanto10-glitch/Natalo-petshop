import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { PrintButton } from "@/components/PrintButton";

const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
const waNumber = process.env.NEXT_PUBLIC_WHATSAPP_NUMBER || "";
const storeAddress = process.env.NEXT_PUBLIC_STORE_ADDRESS || "Alamat toko belum diisi";

const PAY_LABELS: Record<string, string> = {
  UNPAID: "Belum Bayar",
  PENDING: "Menunggu",
  PAID: "Lunas ✓",
  FAILED: "Gagal",
  EXPIRED: "Expired",
  REFUNDED: "Refund",
};

export default async function PrintLabelPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const order = await prisma.order.findUnique({
    where: { id },
    include: { items: { select: { name: true, quantity: true } } },
  });

  if (!order) return notFound();

  const orderStatusUrl = `${siteUrl}/order-status?order=${encodeURIComponent(order.orderNumber)}`;
  const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=80x80&data=${encodeURIComponent(orderStatusUrl)}&bgcolor=ffffff&color=000000&margin=2`;

  const orderDate = new Date(order.createdAt).toLocaleDateString("id-ID", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  });

  const courierInfo = [order.courierCode, order.courierService].filter(Boolean).join(" ").toUpperCase() || "—";

  return (
    <div id="print-label-root" className="min-h-screen bg-gray-100 p-4 print:bg-white print:p-0">
      {/* Toolbar — hidden on print */}
      <div className="print-hidden mb-4 flex flex-wrap items-center gap-3">
        <Link
          href={`/admin/orders/${id}`}
          className="flex items-center gap-2 rounded-full border border-zinc-200 px-4 py-2.5 text-sm font-bold text-zinc-700 hover:border-zinc-400"
        >
          ← Kembali
        </Link>
        <PrintButton />
        <p className="text-sm text-gray-500">Ukuran label: 100 × 150 mm</p>
      </div>

      {/* ── Label ───────────────────────────────────────────────── */}
      <section
        className="shipping-label mx-auto bg-white shadow print:shadow-none"
        style={{
          width: "100mm",
          height: "150mm",
          fontFamily: "Arial, sans-serif",
          fontSize: "9pt",
          padding: "4mm",
          boxSizing: "border-box",
          display: "flex",
          flexDirection: "column",
          gap: 0,
        }}
      >
        {/* Header — pengirim */}
        <header
          style={{
            borderBottom: "1.5px solid black",
            paddingBottom: "3mm",
            marginBottom: "3mm",
          }}
        >
          <p style={{ fontWeight: "bold", fontSize: "10pt", lineHeight: 1.3 }}>
            {brand.toUpperCase()}
          </p>
          {waNumber && (
            <p style={{ lineHeight: 1.4 }}>WA: {waNumber}</p>
          )}
          <p style={{ lineHeight: 1.4 }}>{storeAddress}</p>
        </header>

        {/* Order info */}
        <section
          style={{
            borderBottom: "1px solid black",
            paddingBottom: "3mm",
            marginBottom: "3mm",
            display: "flex",
            justifyContent: "space-between",
            gap: "4mm",
          }}
        >
          <div>
            <p style={{ fontWeight: "bold", fontSize: "8pt", color: "#555" }}>NO. ORDER</p>
            <p style={{ fontWeight: "bold", fontSize: "10pt" }}>{order.orderNumber}</p>
          </div>
          <div style={{ textAlign: "right" }}>
            <p style={{ fontWeight: "bold", fontSize: "8pt", color: "#555" }}>TANGGAL</p>
            <p>{orderDate}</p>
          </div>
          <div style={{ textAlign: "right" }}>
            <p style={{ fontWeight: "bold", fontSize: "8pt", color: "#555" }}>KURIR</p>
            <p>{courierInfo}</p>
          </div>
        </section>

        {/* Penerima */}
        <section
          style={{
            borderBottom: "1px solid black",
            paddingBottom: "3mm",
            marginBottom: "3mm",
          }}
        >
          <p style={{ fontWeight: "bold", fontSize: "8pt", color: "#555" }}>PENERIMA</p>
          <p style={{ fontWeight: "bold", fontSize: "11pt", lineHeight: 1.3 }}>
            {order.customerName}
          </p>
          <p style={{ lineHeight: 1.4 }}>{order.customerPhone}</p>

          <p style={{ fontWeight: "bold", fontSize: "8pt", color: "#555", marginTop: "2mm" }}>ALAMAT</p>
          <p style={{ lineHeight: 1.4 }}>
            {order.shippingAddress}
            {order.shippingCity ? `, ${order.shippingCity}` : ""}
            {order.shippingPostalCode ? ` ${order.shippingPostalCode}` : ""}
          </p>
          {order.notes && (
            <p style={{ marginTop: "1mm", lineHeight: 1.4 }}>
              <strong>Catatan:</strong> {order.notes}
            </p>
          )}
        </section>

        {/* Produk */}
        <section
          style={{
            borderBottom: "1px solid black",
            paddingBottom: "3mm",
            marginBottom: "3mm",
            flex: 1,
            overflow: "hidden",
          }}
        >
          <p style={{ fontWeight: "bold", fontSize: "8pt", color: "#555" }}>PRODUK</p>
          <ul style={{ margin: "1mm 0 0", padding: 0, listStyle: "none", lineHeight: 1.5 }}>
            {order.items.map((item, i) => (
              <li key={i}>
                {item.quantity}× {item.name}
              </li>
            ))}
          </ul>
        </section>

        {/* Total + QR */}
        <section
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            gap: "3mm",
          }}
        >
          <div style={{ flex: 1 }}>
            <div style={{ display: "flex", gap: "6mm", marginBottom: "2mm" }}>
              <div>
                <p style={{ fontWeight: "bold", fontSize: "8pt", color: "#555" }}>TOTAL</p>
                <p style={{ fontWeight: "bold", fontSize: "11pt" }}>{formatRupiah(order.total)}</p>
              </div>
              <div>
                <p style={{ fontWeight: "bold", fontSize: "8pt", color: "#555" }}>PEMBAYARAN</p>
                <p style={{ fontWeight: "bold" }}>{PAY_LABELS[order.paymentStatus] ?? order.paymentStatus}</p>
              </div>
            </div>
            {order.trackingNumber && (
              <p style={{ fontSize: "8pt" }}>
                <strong>Resi:</strong> {order.trackingNumber}
              </p>
            )}
          </div>

          {/* QR Code */}
          <div style={{ textAlign: "center", flexShrink: 0 }}>
            <Image
              src={qrUrl}
              alt="QR Order"
              width={80}
              height={80}
              unoptimized
              style={{ display: "block", border: "1px solid #ddd" }}
            />
            <p style={{ fontSize: "7pt", marginTop: "1mm", color: "#555" }}>Cek status</p>
          </div>
        </section>

        {/* Footer */}
        <footer
          style={{
            textAlign: "center",
            fontSize: "7.5pt",
            color: "#666",
            borderTop: "1px solid #eee",
            paddingTop: "2mm",
            marginTop: "2mm",
          }}
        >
          Terima kasih sudah belanja di {brand} 🐾
        </footer>
      </section>
    </div>
  );
}
