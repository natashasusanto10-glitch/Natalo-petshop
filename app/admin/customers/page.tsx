import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { PageHeader, EmptyState, Badge, Button, AdminPage } from "@/components/admin/ui";
import { customerSearchWhere } from "@/lib/admin-search";
import { parsePageParam } from "@/lib/admin/pagination";

const PAGE_SIZE = 20;

export default async function AdminCustomersPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; q?: string }>;
}) {
  await requireAdminSession();

  const { page: pageStr, q } = await searchParams;
  const page = parsePageParam(pageStr);
  const search = q?.trim() ?? "";

  // Nama / email / HP / username. Satu objek `where` dipakai bersama daftar
  // DAN penghitungnya supaya nomor halaman tidak pernah menjanjikan halaman
  // yang isinya kosong.
  const searchWhere = customerSearchWhere(search);
  const where = {
    role: "CUSTOMER",
    ...(searchWhere ? { AND: searchWhere.AND } : {}),
  };

  const [customers, total] = await Promise.all([
    prisma.user.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
      include: { _count: { select: { orders: true } } },
    }),
    prisma.user.count({ where }),
  ]);

  const totalPages = Math.ceil(total / PAGE_SIZE);

  // Pencarian ikut terbawa saat pindah halaman — kalau tidak, halaman 2
  // diam-diam kembali menampilkan seluruh customer.
  const pageHref = (target: number) => {
    const sp = new URLSearchParams();
    if (search) sp.set("q", search);
    if (target > 1) sp.set("page", String(target));
    const str = sp.toString();
    return `/admin/customers${str ? `?${str}` : ""}`;
  };

  return (
    <AdminPage maxWidth="lg">
      <PageHeader
        title="Customer"
        subtitle={
          search
            ? `${total} customer cocok dengan "${search}".`
            : `${total} customer terdaftar.`
        }
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

      {/* Kotak cari — CS sering hanya pegang nomor HP atau email saat
          customer menghubungi, jadi keempatnya dicari sekaligus. */}
      <form className="mt-4 flex gap-2" method="GET" action="/admin/customers">
        <input
          type="search"
          name="q"
          defaultValue={search}
          aria-label="Cari nama, email, nomor HP, atau username customer"
          placeholder="🔍 Cari nama / email / no. HP / username..."
          className="min-w-0 flex-1 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-natalo-600"
        />
        <Button type="submit">Cari</Button>
        {search && (
          <Button href="/admin/customers" variant="secondary">
            Reset
          </Button>
        )}
      </form>

      {customers.length === 0 ? (
        <div className="mt-6 rounded-2xl border border-zinc-200 bg-white">
          <EmptyState
            icon={search ? "🔍" : "👥"}
            title={
              search ? `Tidak ada customer cocok "${search}"` : "Belum ada customer"
            }
            description={
              search
                ? "Coba kata kunci lain — nama, email, nomor HP, atau username."
                : "Customer akan terdaftar setelah mereka register dari mobile app."
            }
            size="full"
          />
        </div>
      ) : (
        <>
          {/* Mobile card list */}
          <div className="mt-6 space-y-3 md:hidden">
            {customers.map((customer) => {
              const initial = customer.name?.[0]?.toUpperCase() ?? "?";
              return (
                <div
                  key={customer.id}
                  className="rounded-2xl border border-zinc-200 bg-white p-4 transition hover:border-zinc-300"
                >
                  <div className="flex items-start gap-3">
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-natalo-50 text-sm font-black text-natalo-700">
                      {initial}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start justify-between gap-2">
                        <p className="truncate font-bold text-zinc-900">
                          {customer.name}
                        </p>
                        <Badge variant="info">
                          {customer._count.orders}× order
                        </Badge>
                      </div>
                      {customer.email && (
                        <p className="mt-0.5 truncate text-xs text-zinc-500">
                          {customer.email}
                        </p>
                      )}
                      {customer.phone && (
                        <p className="mt-0.5 truncate text-xs text-zinc-500">
                          {customer.phone}
                        </p>
                      )}
                      <p className="mt-1.5 text-[11px] text-zinc-600">
                        Bergabung{" "}
                        {new Date(customer.createdAt).toLocaleDateString(
                          "id-ID",
                          {
                            day: "numeric",
                            month: "short",
                            year: "numeric",
                          },
                        )}
                      </p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>

          {/* Desktop table */}
          <div className="mt-6 hidden overflow-hidden rounded-2xl border border-zinc-200 bg-white md:block">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-zinc-100 bg-zinc-50/50">
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Nama
                    </th>
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Email / HP
                    </th>
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Order
                    </th>
                    <th className="hidden px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500 lg:table-cell">
                      Bergabung
                    </th>
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
                            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-natalo-50 text-xs font-black text-natalo-700">
                              {initial}
                            </div>
                            <p className="font-bold text-zinc-900">
                              {customer.name}
                            </p>
                          </div>
                        </td>
                        <td className="px-5 py-4 text-zinc-500">
                          <p className="text-xs">{customer.email ?? "—"}</p>
                          <p className="text-[11px] text-zinc-600">
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
                            },
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}

      {totalPages > 1 && (
        <div className="mt-6 flex items-center justify-between">
          <p className="text-sm text-zinc-500">
            Halaman{" "}
            <span className="font-black text-zinc-950">{page}</span> dari{" "}
            <span className="font-black text-zinc-950">{totalPages}</span>
          </p>
          <div className="flex gap-2">
            {page > 1 && (
              <Button
                href={pageHref(page - 1)}
                variant="secondary"
                size="sm"
              >
                ← Sebelumnya
              </Button>
            )}
            {page < totalPages && (
              <Button href={pageHref(page + 1)} size="sm">
                Berikutnya →
              </Button>
            )}
          </div>
        </div>
      )}
    </AdminPage>
  );
}
