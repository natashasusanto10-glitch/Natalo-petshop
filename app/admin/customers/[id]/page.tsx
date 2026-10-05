import { notFound } from "next/navigation";
import { OrderStatus } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { parsePageParam } from "@/lib/admin/pagination";
import { CustomerDetailView } from "@/components/admin/views/CustomerDetailView";

export const dynamic = "force-dynamic";
const PAGE_SIZE = 20;

export default async function CustomerDetailPage({ params, searchParams }: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ page?: string; q?: string; fromPage?: string }>;
}) {
  await requireAdminSession();
  const { id } = await params;
  const sp = await searchParams;
  const page = parsePageParam(sp.page);
  const back = new URLSearchParams();
  if (sp.q?.trim()) back.set("q", sp.q.trim().slice(0, 100));
  const fromPage = parsePageParam(sp.fromPage);
  if (fromPage > 1) back.set("page", String(fromPage));
  const context = new URLSearchParams();
  if (sp.q?.trim()) context.set("q", sp.q.trim().slice(0, 100));
  if (fromPage > 1) context.set("fromPage", String(fromPage));
  const customer = await prisma.user.findFirst({
    where: { id, role: "CUSTOMER" },
    select: { id: true, name: true, username: true, email: true, phone: true, createdAt: true },
  });
  if (!customer) notFound();

  const where = { userId: id };
  const [total, paid, ongoing] = await Promise.all([
    prisma.order.count({ where }),
    prisma.order.count({ where: { ...where, paymentStatus: "PAID", status: { notIn: [OrderStatus.CANCELLED, OrderStatus.REFUNDED] } } }),
    prisma.order.count({ where: { ...where, status: { in: [OrderStatus.PENDING, OrderStatus.PAID, OrderStatus.PROCESSING, OrderStatus.READY_FOR_PICKUP, OrderStatus.SHIPPED] } } }),
  ]);
  const totalPages = Math.ceil(total / PAGE_SIZE);
  const orders = page > Math.max(1, totalPages) ? [] : await prisma.order.findMany({
    where,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    skip: (page - 1) * PAGE_SIZE,
    take: PAGE_SIZE,
    select: { id: true, orderNumber: true, createdAt: true, status: true, paymentStatus: true, total: true },
  });
  return <CustomerDetailView customer={customer} orders={orders} total={total} paid={paid} ongoing={ongoing} page={page} totalPages={totalPages} backHref={`/admin/customers${back.size ? `?${back}` : ""}`} context={context.toString()} />;
}
