/**
 * PUT /api/admin/products/[id]/variants
 *
 * Simpan/update struktur varian produk secara atomik.
 * Attribute/options diperbarui; varian yang dipertahankan tetap memakai ID lama.
 * Kombinasi yang dihapus diarsipkan untuk mempertahankan riwayat pesanan.
 */

import { after, NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { syncProduct } from "@/lib/search";
import {
  putVariantsPayloadSchema,
  formatVariantIssues,
} from "@/lib/validators/variant-schema";
import { saveAdminVariants } from "@/lib/product/save-admin-variants";

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const csrfReject = assertSameOrigin(request);
    if (csrfReject) return csrfReject;

    const session = await getSession("ADMIN");
    if (!session || session.role !== "ADMIN")
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const { id: productId } = await params;
    const parsed = putVariantsPayloadSchema.safeParse(await request.json());
    if (!parsed.success) {
      return NextResponse.json(
        {
          error: formatVariantIssues(parsed.error.issues),
          fields: parsed.error.flatten().fieldErrors,
          // Detail per-issue (path + pesan) supaya UI bisa tunjuk baris/field
          // mana yang salah, bukan cuma pesan generik.
          issues: parsed.error.issues.map((i) => ({
            path: i.path,
            message: i.message,
          })),
        },
        { status: 422 }
      );
    }
    const { hasVariants } = parsed.data;

    // Validasi produk ada
    const product = await prisma.product.findUnique({
      where: { id: productId },
    });
    if (!product)
      return NextResponse.json(
        { error: "Produk tidak ditemukan" },
        { status: 404 }
      );

    await prisma.$transaction(async (tx) => {
      await tx.product.update({
        where: { id: productId },
        data: { hasVariants },
      });
      await saveAdminVariants(tx, productId, parsed.data);
    });

    // Via after() — fire-and-forget promise bisa dibekukan Vercel sebelum
    // jalan → index pencarian basi (harga/stok lama). Pola sama dengan
    // bulk route.
    after(() =>
      syncProduct(productId).catch((error) => {
        console.error("[variants PUT syncProduct]", error);
      })
    );

    // Restock trigger — kalau Product.stock berubah dari 0 ke >0
    // (aggregate dari sum variant stocks di transaction), notify
    // subscriber yang mendaftar untuk produk ini (variantId=null).
    // Retained variants keep IDs and their subscriber associations.
    if (product.stock === 0) {
      const refreshed = await prisma.product.findUnique({
        where: { id: productId },
        select: { stock: true },
      });
      if (refreshed && refreshed.stock > 0) {
        // Via after() — fire-and-forget promise bisa dibekukan Vercel
        // sebelum jalan → subscriber "Ingatkan saya" tidak pernah dapat
        // push stok-kembali. Fan-out ke banyak subscriber, jangan tahan
        // response admin.
        after(async () => {
          const { sendBackInStockPush } = await import("@/lib/push-marketing");
          await sendBackInStockPush(productId, null).catch((err) => {
            console.warn("[variants PUT back-in-stock]:", err);
          });
        });
      }
    }

    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("[variants PUT]", error);
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Gagal menyimpan varian",
      },
      { status: 500 }
    );
  }
}

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN")
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { id: productId } = await params;

  const product = await prisma.product.findUnique({
    where: { id: productId },
    include: {
      variantAttrs: {
        orderBy: { position: "asc" },
        include: { options: { orderBy: { position: "asc" } } },
      },
      variants: {
        where: { deletedAt: null },
        include: { options: { select: { optionId: true } } },
        orderBy: { createdAt: "asc" },
      },
    },
  });

  if (!product)
    return NextResponse.json({ error: "Not found" }, { status: 404 });

  return NextResponse.json({
    hasVariants: product.hasVariants,
    attributes: product.variantAttrs,
    variants: product.variants,
  });
}
