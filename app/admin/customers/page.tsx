import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";

const PAGE_SIZE = 20;

export default async function AdminCustomersPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string }>;
}) {
  await requireAdminSession();

  const { page: pageStr } = await searchParams;
  const page = Math.max(1, parseInt(pageStr || "1", 10));

  const [customers, total] = await Promise.all([
    prisma.user.findMany({
      where: { role: "CUSTOMER" },
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
      include: { _count: { select: { orders: true } } },
    }),
    prisma.user.count({ where: { role: "CUSTOMER" } }),
  ]);

  const totalPages = Math.ceil(total / PAGE_SIZE);

  return (
    <div className="mx-auto max-w-4xl px-4 py-5 md:py-10">
      <div>
        <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
          Customer
        </h1>
        <p className="mt-1 text-sm text-zinc-500">
          {total} customer terdaftar.
        </p>
      </div>

      {customers.length === 0 ? (
        <div className="mt-5 rounded-2xl border border-zinc-200 bg-white p-12 text-center md:mt-6 md:rounded-3xl">
          <p className="text-2xl">👥</p>
          <p className="mt-3 font-semibold text-zinc-700">
            Belum ada customer
          </p>
        </div>
      ) : (
        <>
          {/* Mobile card list */}
          <div className="mt-5 space-y-3 md:hidden">
            {customers.map((customer) => (
              <div key={customer.id} className="rounded-2xl border border-zinc-200 bg-white p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="truncate font-semibold text-zinc-900">{customer.name}</p>
                    {customer.email && (
                      <p className="mt-0.5 truncate text-xs text-zinc-500">{customer.email}</p>
                    )}
                    {customer.phone && (
                      <p className="mt-0.5 truncate text-xs text-zinc-500">{customer.phone}</p>
                    )}
                  </div>
                  <span className="shrink-0 rounded-full bg-zinc-100 px-2.5 py-1 text-xs font-bold text-zinc-700">
                    {customer._count.orders}× order
                  </span>
                </div>
                <p className="mt-2 text-[11px] text-zinc-400">
                  Bergabung {new Date(customer.createdAt).toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric" })}
                </p>
              </div>
            ))}
          </div>

          {/* Desktop table */}
          <div className="mt-6 hidden overflow-hidden rounded-3xl border border-zinc-200 bg-white md:block">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-zinc-100 bg-zinc-50">
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600">
                      Nama
                    </th>
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600">
                      Email / HP
                    </th>
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600">
                      Order
                    </th>
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600 hidden lg:table-cell">
                      Bergabung
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {customers.map((customer) => (
                    <tr
                      key={customer.id}
                      className="border-b border-zinc-100 last:border-0 hover:bg-zinc-50 transition"
                    >
                      <td className="px-5 py-4">
                        <p className="font-semibold text-zinc-900">
                          {customer.name}
                        </p>
                      </td>
                      <td className="px-5 py-4 text-zinc-500">
                        <p>{customer.email ?? "-"}</p>
                        <p className="text-xs">{customer.phone ?? ""}</p>
                      </td>
                      <td className="px-5 py-4">
                        <span className="rounded-full bg-zinc-100 px-2.5 py-1 text-xs font-bold text-zinc-700">
                          {customer._count.orders}x
                        </span>
                      </td>
                      <td className="px-5 py-4 text-zinc-400 hidden lg:table-cell">
                        {new Date(customer.createdAt).toLocaleDateString(
                          "id-ID",
                          {
                            day: "numeric",
                            month: "short",
                            year: "numeric",
                          }
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}

      {totalPages > 1 && (
        <div className="mt-6 flex items-center justify-between">
          <p className="text-sm text-zinc-500">
            Halaman {page} dari {totalPages}
          </p>
          <div className="flex gap-2">
            {page > 1 && (
              <a
                href={`/admin/customers?page=${page - 1}`}
                className="rounded-full border border-zinc-200 px-4 py-2 text-sm font-bold hover:border-zinc-400"
              >
                ← Sebelumnya
              </a>
            )}
            {page < totalPages && (
              <a
                href={`/admin/customers?page=${page + 1}`}
                className="rounded-full bg-zinc-950 px-4 py-2 text-sm font-bold text-white"
              >
                Berikutnya →
              </a>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
