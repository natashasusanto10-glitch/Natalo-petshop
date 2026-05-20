/**
 * POST /api/admin/flash-sale/end
 *
 * End Flash Sale lebih awal untuk satu produk: clear
 * Product.flashSaleEndsAt + Product.discountPrice.
 *
 * Body: { productId: string }
 *
 * Catatan: tidak hapus produk, hanya hentikan promosi-nya. Customer
 * akan langsung lihat harga normal kembali.
 */
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";

const schema = z.object({
  productId: z.string().trim().min(1),
});

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const parsed = schema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: "productId required" },
      { status: 400 },
    );
  }

  const product = await prisma.product.findUnique({
    where: { id: parsed.data.productId },
    select: { id: true, name: true },
  });
  if (!product) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }

  await prisma.product.update({
    where: { id: product.id },
    data: {
      flashSaleEndsAt: null,
      discountPrice: null,
    },
  });

  return NextResponse.json({ ok: true });
}
