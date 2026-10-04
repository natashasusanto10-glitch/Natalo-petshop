import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { CustomersView } from "@/components/admin/views/CustomersView";
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
    <CustomersView
      customers={customers}
      total={total}
      search={search}
      page={page}
      totalPages={totalPages}
      pageHref={pageHref}
    />
  );
}
