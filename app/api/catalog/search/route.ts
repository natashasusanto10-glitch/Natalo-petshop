import { NextRequest, NextResponse } from "next/server";
import { verifyStaffRequest } from "@/lib/chat/staff-auth";
import { isChatEnabled } from "@/app/api/chat/config/route";
import { getProducts } from "@/lib/products";
import { toCatalogCard } from "@/lib/chat/catalog-card";

export const dynamic = "force-dynamic";

function parsePositiveInt(value: string | null, fallback: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : fallback;
}

export async function GET(request: NextRequest) {
  const auth = await verifyStaffRequest(request);
  if (auth instanceof NextResponse) return auth;

  // Kill-switch (fix C1) — simetris dengan endpoint customer Plan 2;
  // jangan biarkan staff share produk ke chat saat chat mati.
  if (!(await isChatEnabled())) {
    return NextResponse.json({ error: "Chat sedang nonaktif." }, { status: 503 });
  }

  const sp = request.nextUrl.searchParams;
  const q = (sp.get("q") ?? sp.get("search") ?? "").trim();
  const limit = Math.min(50, parsePositiveInt(sp.get("limit"), 24));
  const cursor = Math.max(0, parsePositiveInt(sp.get("cursor"), 0));

  const products = await getProducts({
    search: q || undefined,
    take: limit,
    skip: cursor,
  });
  const items = products.map(toCatalogCard);

  return NextResponse.json({ items });
}
