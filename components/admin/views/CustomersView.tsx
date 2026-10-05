import Link from "next/link";
import {
  PageHeader,
  EmptyState,
  Badge,
  Button,
  AdminPage,
  Pagination,
} from "@/components/admin/ui";
export type CustomersViewProps = {
  customers: Array<{
    id: string;
    name: string | null;
    email: string | null;
    phone: string | null;
    createdAt: Date;
    _count: { orders: number };
  }>;
  total: number;
  search: string;
  page: number;
  totalPages: number;
  pageHref: (page: number) => string;
};
export function CustomersView({
  customers,
  total,
  search,
  page,
  totalPages,
  pageHref,
}: CustomersViewProps) {
  const customerHref = (id: string) => {
    const context = new URLSearchParams();
    if (search) context.set("q", search);
    if (page > 1) context.set("fromPage", String(page));
    return `/admin/customers/${id}${context.size ? `?${context}` : ""}`;
  };
  return (
    <AdminPage
      maxWidth="xl"
      className="admin-operational-page admin-refined-page"
    >
      <PageHeader
        eyebrow="Layanan pelanggan"
        title="Pelanggan"
        subtitle={
          search
            ? `${total} pelanggan cocok dengan "${search}".`
            : `${total} pelanggan terdaftar.`
        }
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            Kembali ke ringkasan
          </Button>
        }
      />

      <section className="admin-list-workspace" aria-label="Daftar pelanggan">
        {/* Kotak cari — CS sering hanya pegang nomor HP atau email saat
          customer menghubungi, jadi keempatnya dicari sekaligus. */}
        <form
          className="admin-searchbar"
          method="GET"
          action="/admin/customers"
        >
          <input
            type="search"
            name="q"
            defaultValue={search}
            aria-label="Cari nama, email, nomor HP, atau username pelanggan"
            placeholder="Cari nama, email, nomor HP, atau username"
            className="min-w-0 flex-1 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-natalo-600"
          />
          <Button type="submit">Cari</Button>
          {search && (
            <Button href="/admin/customers" variant="secondary">
              Atur ulang
            </Button>
          )}
        </form>

        {total > 0 && page > totalPages ? (
          <div className="mt-6 rounded-2xl border border-zinc-200 bg-white">
            <EmptyState title="Halaman tidak tersedia" description={`Daftar ini hanya sampai halaman ${totalPages}.`} action={{ label: "Kembali ke halaman pertama", href: pageHref(1) }} size="full" />
          </div>
        ) : customers.length === 0 ? (
          <div className="mt-6 rounded-2xl border border-zinc-200 bg-white">
            <EmptyState
              icon={search ? "🔍" : "👥"}
              title={
                search
                  ? `Tidak ada pelanggan cocok "${search}"`
                  : "Belum ada pelanggan"
              }
              description={
                search
                  ? "Coba kata kunci lain — nama, email, nomor HP, atau username."
                  : "Pelanggan muncul setelah mendaftar melalui aplikasi."
              }
              size="full"
            />
          </div>
        ) : (
          <>
            {/* Mobile card list */}
            <div className="mt-6 space-y-3 xl:hidden">
              {customers.map((customer) => {
                const initial = customer.name?.[0]?.toUpperCase() ?? "?";
                return (
                  <div
                    key={customer.id}
                    className="rounded-2xl border border-zinc-200 bg-white p-4 transition hover:border-zinc-300"
                  >
                    <div className="flex items-start gap-3">
                      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-natalo-50 text-sm font-semibold text-natalo-700">
                        {initial}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-start justify-between gap-2">
                          <Link href={customerHref(customer.id)} className="break-words font-semibold text-natalo-700 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-natalo-600">
                            {customer.name || "Pelanggan tanpa nama"}
                          </Link>
                          <span className="shrink-0 whitespace-nowrap"><Badge variant="info">
                            {customer._count.orders} pesanan
                          </Badge></span>
                        </div>
                        {customer.email && (
                          <p className="mt-0.5 break-all text-sm text-zinc-600">
                            {customer.email}
                          </p>
                        )}
                        {customer.phone && (
                          <p className="mt-0.5 break-words text-sm text-zinc-600">
                            {customer.phone}
                          </p>
                        )}
                        <p className="mt-1.5 text-xs text-zinc-600">
                          Bergabung{" "}
                          {new Date(customer.createdAt).toLocaleDateString(
                            "id-ID",
                            {
                              day: "numeric",
                              month: "short",
                              year: "numeric",
                              timeZone: "Asia/Jakarta",
                            }
                          )}
                        </p>
                        <Link href={customerHref(customer.id)} className="mt-2 inline-flex min-h-11 items-center text-sm font-semibold text-natalo-700 hover:underline">Lihat detail &amp; riwayat →</Link>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Desktop table */}
            <div className="mt-6 hidden overflow-hidden rounded-2xl border border-zinc-200 bg-white xl:block">
              <div className="overflow-x-auto">
                <table className="admin-data-table w-full text-sm">
                  <thead>
                    <tr className="border-b border-zinc-100 bg-zinc-50/50">
                      <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                        Nama
                      </th>
                      <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                        Email / HP
                      </th>
                      <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                        Pesanan
                      </th>
                      <th className="hidden px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500 lg:table-cell">
                        Bergabung
                      </th>
                      <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">Aksi</th>
                    </tr>
                  </thead>
                  <tbody>
                    {customers.map((customer) => {
                      const initial = customer.name?.[0]?.toUpperCase() ?? "?";
                      return (
                        <tr
                          key={customer.id}
                          className="border-b border-zinc-100 transition last:border-0 hover:bg-natalo-50/40"
                        >
                          <td className="px-5 py-4">
                            <div className="flex items-center gap-2.5">
                              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-natalo-50 text-xs font-semibold text-natalo-700">
                                {initial}
                              </div>
                              <Link href={customerHref(customer.id)} className="font-semibold text-natalo-700 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-natalo-600">
                                {customer.name || "Pelanggan tanpa nama"}
                              </Link>
                            </div>
                          </td>
                          <td className="px-5 py-4 text-zinc-500">
                            <p className="text-xs">{customer.email ?? "—"}</p>
                            <p className="text-xs text-zinc-600">
                              {customer.phone ?? ""}
                            </p>
                          </td>
                          <td className="px-5 py-4">
                            <Badge variant="info" size="md">
                              {customer._count.orders}×
                            </Badge>
                          </td>
                          <td className="hidden px-5 py-4 text-xs text-zinc-500 lg:table-cell">
                            {new Date(customer.createdAt).toLocaleDateString(
                              "id-ID",
                              {
                                day: "numeric",
                                month: "short",
                                year: "numeric",
                                timeZone: "Asia/Jakarta",
                              }
                            )}
                          </td>
                          <td className="px-5 py-4"><Button href={customerHref(customer.id)} variant="secondary" size="sm">Lihat riwayat</Button></td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        )}

        <Pagination
          currentPage={page}
          totalPages={totalPages}
          hrefFor={pageHref}
          summary={`${total} pelanggan`}
        />
      </section>
    </AdminPage>
  );
}
