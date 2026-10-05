import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") return NextResponse.json({ error: "Akses ditolak." }, { status: 401 });
  const params = request.nextUrl.searchParams;
  const kind = params.get("kind");
  const q = (params.get("q") ?? "").trim().slice(0, 100);
  const ids = [...new Set((params.get("ids") ?? "").split(",").filter(Boolean))].slice(0, 100);
  const contains = { contains: q, mode: "insensitive" as const };
  const respond = (options: { id: string; name: string; key?: string }[], total: number) => NextResponse.json({ options, total }, { headers: { "Cache-Control": "private, no-store" } });
  if (kind === "category") {
    const where = ids.length ? { OR: [{ id: { in: ids } }, { slug: { in: ids } }] } : { name: contains };
    const [rows, total] = await Promise.all([prisma.category.findMany({ where, orderBy: { name: "asc" }, take: ids.length ? 100 : 25, select: { id: true, name: true, slug: true } }), prisma.category.count({ where })]);
    return respond(rows.map(r => ({ id: r.id, name: r.name, key: r.slug })), total);
  }
  if (kind === "product") {
    const where = ids.length ? { id: { in: ids } } : { isActive: true, OR: [{ name: contains }, { sku: contains }] };
    const [rows, total] = await Promise.all([prisma.product.findMany({ where, orderBy: { name: "asc" }, take: ids.length ? 100 : 25, select: { id: true, name: true } }), prisma.product.count({ where })]);
    return respond(rows, total);
  }
  if (kind === "user") {
    if (!ids.length && q.length < 2) return respond([], 0);
    const where = ids.length ? { id: { in: ids }, role: "CUSTOMER" } : { role: "CUSTOMER", OR: [{ name: contains }, { email: contains }, { phone: contains }] };
    const [rows, total] = await Promise.all([prisma.user.findMany({ where, orderBy: { name: "asc" }, take: ids.length ? 100 : 25, select: { id: true, name: true, email: true, phone: true } }), prisma.user.count({ where })]);
    return respond(rows.map(r => ({ id: r.id, name: `${r.name ?? "Pelanggan"} · ${r.email ?? r.phone ?? "Tanpa kontak"}` })), total);
  }
  return NextResponse.json({ error: "Pilihan tidak valid." }, { status: 400 });
}
