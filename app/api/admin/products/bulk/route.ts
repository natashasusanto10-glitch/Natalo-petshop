import { NextRequest, NextResponse } from "next/server";
import { after } from "next/server";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { deleteProductVideo } from "@/lib/product/product-video";

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

/**
 * POST /api/admin/products/bulk
 *
 * Aksi massal untuk produk terpilih dari halaman admin:
 *  - action: "archive" → set isActive=false (soft, bisa dipulihkan).
 *  - action: "delete"  → hapus permanen produk yang BELUM pernah dipesan;
 *    produk yang pernah dipesan (FK OrderItem → Product) tidak bisa dihapus
 *    permanen, jadi otomatis diarsipkan. Produk yang masih terkait data lain
 *    (mis. ada di keranjang) dihitung sebagai gagal dan dilaporkan, tanpa
 *    menggagalkan sisa batch.
 *
 * Body: { ids: string[], action: "delete" | "archive" }
 * Return: { deleted, archived, failed }
 */
export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  const rawIds: unknown = body?.ids;
  const action: unknown = body?.action;

  if (action !== "delete" && action !== "archive") {
    return NextResponse.json({ error: "Aksi tidak valid" }, { status: 400 });
  }
  if (!Array.isArray(rawIds) || rawIds.some((id) => typeof id !== "string" || !id)) {
    return NextResponse.json({ error: "Daftar produk tidak valid" }, { status: 400 });
  }
  const ids = [...new Set(rawIds as string[])];
  if (ids.length === 0 || ids.length > MAX_BULK) {
    return NextResponse.json({ error: `Pilih 1–${MAX_BULK} produk` }, { status: 400 });
  }

  // ── Arsipkan massal (soft, reversibel) ──────────────────────────────
  if (action === "archive") {
    const res = await prisma.product.updateMany({
      where: { id: { in: ids } },
      data: { isActive: false },
    });
    after(async () => {
      try {
        const { syncProduct } = await import("@/lib/search");
        await Promise.all(
          ids.map((id) =>
            syncProduct(id).catch((err) =>
              console.error(`[bulk-archive] sync ${id} gagal:`, err),
            ),
          ),
        );
      } catch (err) {
        console.error("[bulk-archive] import search gagal:", err);
      }
    });
    revalidatePath("/admin/products");
    revalidatePath("/admin/stock");
    revalidatePath("/admin/dashboard");
    return NextResponse.json({ deleted: 0, archived: res.count, failed: 0 });
  }

  // ── Hapus massal ────────────────────────────────────────────────────
  // Cari produk yang pernah dipesan → diarsipkan (bukan dihapus).
  const orderedRows = await prisma.orderItem.findMany({
    where: { productId: { in: ids } },
    select: { productId: true },
    distinct: ["productId"],
  });
  const orderedSet = new Set(orderedRows.map((r) => r.productId));
  const toArchive = ids.filter((id) => orderedSet.has(id));
  const toDelete = ids.filter((id) => !orderedSet.has(id));

  if (toArchive.length > 0) {
    await prisma.product.updateMany({
      where: { id: { in: toArchive } },
      data: { isActive: false },
    });
  }

  // Best-effort: hapus video Bunny milik produk yang BENAR-BENAR akan
  // di-hard-delete (bukan yang diarsipkan). Bukan wajib untuk kebenaran —
  // cron GC (Task 9) tetap menyapu video orphan kalau ini gagal, jadi tidak
  // boleh menggagalkan/menunda delete produk di bawah.
  const withVideo = await prisma.product.findMany({
    where: { id: { in: toDelete }, videoGuid: { not: null } },
    select: { videoGuid: true },
  });
  await Promise.allSettled(
    withVideo.map((p) => (p.videoGuid ? deleteProductVideo(p.videoGuid) : Promise.resolve())),
  );

  // Hapus per-item supaya satu produk yang masih terkait data lain tidak
  // menggagalkan seluruh batch (cascade menghapus varian/review/favorite).
  const deletedIds: string[] = [];
  const failed: string[] = [];
  for (const id of toDelete) {
    try {
      await prisma.product.delete({ where: { id } });
      deletedIds.push(id);
    } catch {
      failed.push(id);
    }
  }

  after(async () => {
    try {
      const { syncProduct, deleteProductFromIndex } = await import("@/lib/search");
      await Promise.all([
        ...deletedIds.map((id) =>
          deleteProductFromIndex(id).catch((err) =>
            console.error(`[bulk-delete] hapus index ${id} gagal:`, err),
          ),
        ),
        ...toArchive.map((id) =>
          syncProduct(id).catch((err) =>
            console.error(`[bulk-delete] sync ${id} gagal:`, err),
          ),
        ),
      ]);
    } catch (err) {
      console.error("[bulk-delete] import search gagal:", err);
    }
  });

  revalidatePath("/admin/products");
  revalidatePath("/admin/stock");
  revalidatePath("/admin/dashboard");

  return NextResponse.json({
    deleted: deletedIds.length,
    archived: toArchive.length,
    failed: failed.length,
  });
}
