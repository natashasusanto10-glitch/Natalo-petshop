import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  generateFeedPost,
  GenerateFeedPostError,
} from "@/lib/ai/generate-feed-post";

/**
 * POST /api/admin/feed/generate-post
 *
 * Generate judul + caption feed via Claude API dari topik singkat admin +
 * (opsional) nama produk yang di-tag. Dipakai tombol "✨ Generate" di
 * halaman "Buat Post Feed" (AdminFeedCreateClient).
 *
 * Body: {
 *   topic?: string;
 *   kind?: "VIDEO_ONLY" | "VIDEO_PRODUCT" | "PROMO";
 *   productIds?: string[];   // maks 5 dipakai sebagai konteks
 * }
 * Return: { title, caption }
 */
const VALID_KINDS = new Set(["VIDEO_ONLY", "VIDEO_PRODUCT", "PROMO"]);

export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    topic?: unknown;
    kind?: unknown;
    productIds?: unknown;
  };

  const topic = typeof body.topic === "string" ? body.topic : "";
  const kind =
    typeof body.kind === "string" && VALID_KINDS.has(body.kind)
      ? (body.kind as "VIDEO_ONLY" | "VIDEO_PRODUCT" | "PROMO")
      : null;
  const productIds = Array.isArray(body.productIds)
    ? body.productIds.filter((v): v is string => typeof v === "string").slice(0, 5)
    : [];

  let productNames: string[] = [];
  if (productIds.length > 0) {
    const products = await prisma.product.findMany({
      where: { id: { in: productIds } },
      select: { name: true },
    });
    productNames = products.map((p) => p.name);
  }

  try {
    const result = await generateFeedPost({ topic, kind, productNames });
    return NextResponse.json(result);
  } catch (err) {
    if (err instanceof GenerateFeedPostError) {
      const status =
        err.code === "INVALID_INPUT" || err.code === "MISSING_KEY" ? 400 : 502;
      return NextResponse.json({ error: err.message }, { status });
    }
    const message = err instanceof Error ? err.message : String(err);
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
