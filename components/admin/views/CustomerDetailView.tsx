import Link from "next/link";
import { formatRupiah } from "@/lib/format";
import { orderStatusLabel, paymentStatusLabel } from "@/lib/order-labels";
import { AdminPage, PageHeader, StatCard, Badge, Button, Pagination, EmptyState, STATUS_BADGE_VARIANT, PAY_BADGE_VARIANT } from "@/components/admin/ui";

export type CustomerDetailViewProps = {
  customer: { id: string; name: string | null; username: string | null; email: string | null; phone: string | null; createdAt: Date };
  orders: { id: string; orderNumber: string; createdAt: Date; status: string; paymentStatus: string; total: number }[];
  backHref?: string; context?: string;
  total: number; paid: number; ongoing: number; page: number; totalPages: number;
};
function dateLabel(date: Date) {
  return new Intl.DateTimeFormat("id-ID", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Jakarta" }).format(new Date(date));
}
export function CustomerDetailView({ customer, orders, total, paid, ongoing, page, totalPages, backHref = "/admin/customers", context = "" }: CustomerDetailViewProps) {
  const pageHref = (target: number) => {
    const query = new URLSearchParams(context);
    if (target > 1) query.set("page", String(target));
    return `/admin/customers/${customer.id}${query.size ? `?${query}` : ""}`;
  };
  return <AdminPage maxWidth="xl" className="admin-operational-page admin-refined-page">
    <PageHeader eyebrow="Layanan pelanggan" title={customer.name || "Pelanggan tanpa nama"} subtitle={`Bergabung ${dateLabel(customer.createdAt)}`} actions={<Button href={backHref} variant="secondary" size="sm">Kembali ke pelanggan</Button>} />
    <section aria-label="Informasi pelanggan" className="mt-6 rounded-2xl border border-zinc-200 bg-white p-5">
      <h2 className="font-semibold text-zinc-900">Informasi pelanggan</h2>
      <dl className="mt-4 grid gap-4 text-sm sm:grid-cols-3">
        {[["Email", customer.email], ["Nomor HP", customer.phone], ["Username", customer.username]].map(([label, value]) => <div key={label}><dt className="text-zinc-500">{label}</dt><dd className="mt-1 break-all font-medium text-zinc-900">{value || "Belum diisi"}</dd></div>)}
      </dl>
    </section>
    <section aria-label="Ringkasan pesanan" className="admin-customer-stats mt-4 grid grid-cols-3 gap-2 sm:gap-3">
      <StatCard label="Seluruh pesanan" value={total} helper="Semua status" />
      <StatCard label="Pesanan berjalan" value={ongoing} helper="Belum selesai atau dibatalkan" variant="primary" />
      <StatCard label="Pesanan dibayar" value={paid} helper="Di luar pesanan batal dan refund" variant="success" />
    </section>
    <section className="admin-list-workspace" aria-labelledby="customer-history-title">
      <div className="flex flex-wrap items-center justify-between gap-2"><h2 id="customer-history-title" className="text-lg font-semibold text-zinc-900">Riwayat pesanan</h2><span className="text-sm text-zinc-600">{total} pesanan</span></div>
      {page > Math.max(1, totalPages) ? <EmptyState title="Halaman tidak tersedia" description="Kembali ke halaman pertama untuk melihat riwayat pelanggan." action={{ label: "Halaman pertama", href: pageHref(1) }} size="full" /> : orders.length === 0 ? <EmptyState title="Belum ada pesanan" description="Pesanan yang terhubung dengan akun pelanggan ini akan muncul di sini." size="full" /> : <>
        <div className="mt-4 space-y-3 md:hidden">{orders.map(order => <article key={order.id} className="rounded-2xl border border-zinc-200 bg-white p-4">
          <div className="flex flex-wrap items-center justify-between gap-2"><Link href={`/admin/orders/${order.id}`} className="min-h-11 inline-flex items-center font-semibold text-natalo-700 hover:underline">#{order.orderNumber}</Link><Badge variant={STATUS_BADGE_VARIANT[order.status] ?? "neutral"}>{orderStatusLabel(order.status)}</Badge></div>
          <div className="mt-2 flex flex-wrap items-center justify-between gap-2"><span className="text-sm text-zinc-600">{dateLabel(order.createdAt)}</span><span className="font-semibold tabular-nums">{formatRupiah(order.total)}</span></div>
          <p className="mt-2 text-sm text-zinc-600">Pembayaran: {paymentStatusLabel(order.paymentStatus)}</p>
          <Button href={`/admin/orders/${order.id}`} variant="secondary" size="sm" className="mt-3">Lihat pesanan</Button>
        </article>)}</div>
        <div className="mt-4 hidden overflow-x-auto rounded-2xl border border-zinc-200 md:block"><table className="admin-data-table w-full text-sm">
          <thead><tr>{["Pesanan", "Tanggal (WIB)", "Status", "Pembayaran", "Di luar saldo"].map(label => <th key={label} scope="col" className="bg-zinc-50 px-4 py-3 text-left font-semibold text-zinc-600">{label}</th>)}</tr></thead>
          <tbody>{orders.map(order => <tr key={order.id} className="border-t border-zinc-100 hover:bg-natalo-50/30"><td className="px-4 py-3"><Link href={`/admin/orders/${order.id}`} className="inline-flex min-h-11 items-center font-semibold text-natalo-700 hover:underline">#{order.orderNumber}</Link></td><td className="px-4 py-3 whitespace-nowrap">{dateLabel(order.createdAt)}</td><td className="px-4 py-3"><Badge variant={STATUS_BADGE_VARIANT[order.status] ?? "neutral"}>{orderStatusLabel(order.status)}</Badge></td><td className="px-4 py-3"><Badge variant={PAY_BADGE_VARIANT[order.paymentStatus] ?? "neutral"}>{paymentStatusLabel(order.paymentStatus)}</Badge></td><td className="px-4 py-3 font-medium tabular-nums whitespace-nowrap">{formatRupiah(order.total)}</td></tr>)}</tbody>
        </table></div>
      </>}
      <p className="mt-4 text-xs text-zinc-500">Nominal menunjukkan pembayaran di luar saldo pada pesanan.</p>
      <Pagination currentPage={page} totalPages={totalPages} hrefFor={pageHref} />
    </section>
  </AdminPage>;
}
