import { NextRequest, NextResponse } from "next/server";
import { after } from "next/server";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";

type Update = { id: string; price?: number; stock?: number };

const MAX_BULK = 200;

export async function PATCH(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json();
  if (!Array.isArray(body?.updates)) {
    return NextResponse.json({ error: "Payload tidak valid" }, { status: 400 });
  }
  const updates: Update[] = body.updates;
  if (updates.length === 0 || updates.length > MAX_BULK) {
    return NextResponse.json(
      { error: `Update harus 1–${MAX_BULK} item` },
      { status: 400 }
    );
  }

  for (const u of updates) {
    if (typeof u.id !== "string" || !u.id) {
      return NextResponse.json({ error: "ID tidak valid" }, { status: 400 });
    }
    if (u.price !== undefined && (!Number.isInteger(u.price) || u.price < 0)) {
      return NextResponse.json({ error: "Harga harus angka >= 0" }, { status: 400 });
    }
    if (u.stock !== undefined && (!Number.isInteger(u.stock) || u.stock < 0)) {
      return NextResponse.json({ error: "Stok harus angka >= 0" }, { status: 400 });
    }
    if (u.price === undefined && u.stock === undefined) {
      return NextResponse.json(
        { error: "Setiap item harus punya price atau stock" },
        { status: 400 }
      );
    }
  }

  // Update atomik. Filter hasVariants:false sebagai safety extra —
  // produk dengan varian tidak boleh disentuh di sini (price/stock-nya derived dari variants).
  const results = await prisma.$transaction(
    updates.map((u) =>
      prisma.product.updateMany({
        where: { id: u.id, hasVariants: false },
        data: {
          ...(u.price !== undefined ? { price: u.price } : {}),
          ...(u.stock !== undefined ? { stock: u.stock } : {}),
        },
      })
    )
  );
  const updated = results.reduce((s, r) => s + r.count, 0);

  // Sync search index non-blocking via Next.js `after()` — guarantees
  // function tetap eksekusi setelah response dikirim. Sebelumnya pakai
  // fire-and-forget IIFE yang bisa di-terminate oleh Vercel sebelum
  // search sync selesai → search index stale.
  after(async () => {
    try {
      const { syncProduct } = await import("@/lib/search");
      await Promise.all(
        updates.map((u) =>
          syncProduct(u.id).catch((err) =>
            console.error(`[bulk-sync] product ${u.id} search sync failed:`, err),
          ),
        ),
      );
    } catch (err) {
      console.error("[bulk-sync] failed to import search module:", err);
    }
  });

  // Refresh halaman admin yg tergantung price/stock
  revalidatePath("/admin/products");
  revalidatePath("/admin/stock");
  revalidatePath("/admin/dashboard");

  return NextResponse.json({ updated });
}
