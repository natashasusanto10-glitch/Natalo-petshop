/**
 * POST /api/products/bunny/webhook
 *
 * Callback Bunny Stream saat video PRODUK berubah state encoding.
 * Cari Product by videoGuid, resolusi via resolveProductVideoWebhookUpdate.
 *
 * Body Bunny: { VideoLibraryId, VideoGuid, Status }.
 * Auth opsional: BUNNY_PRODUCT_WEBHOOK_SECRET → header Authorization Bearer.
 */

import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  getProductVideo,
  productPlaylistUrl,
  productThumbnailUrl,
  webhookAuthorized,
} from "@/lib/product/product-video";
import { resolveProductVideoWebhookUpdate } from "@/lib/product/product-video-serialize";

export const dynamic = "force-dynamic";

type WebhookPayload = { VideoGuid?: string; Status?: number };

export async function GET() {
  return NextResponse.json({
    ok: true,
    hint: "POST only — menerima callback Bunny Stream video produk.",
  });
}

export async function POST(request: NextRequest) {
  if (!webhookAuthorized(request.headers.get("authorization"))) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }
  const payload = (await request.json().catch(() => null)) as WebhookPayload | null;
  const guid = payload?.VideoGuid;
  const status = payload?.Status;
  if (!guid || typeof status !== "number") {
    return NextResponse.json({ ok: false, error: "Invalid payload" }, { status: 400 });
  }

  const product = await prisma.product.findUnique({
    where: { videoGuid: guid },
    select: { id: true, videoStatus: true },
  });
  if (!product) {
    return NextResponse.json({ ok: true, skipped: "unknown-guid" });
  }

  // Untuk FINISHED, ambil durasi asli dari Bunny (best-effort).
  const meta =
    status === 4 ? await getProductVideo(guid) : null;

  const update = resolveProductVideoWebhookUpdate({
    status,
    currentStatus: product.videoStatus,
    playlistUrl: productPlaylistUrl(guid),
    thumbnailUrl: productThumbnailUrl(guid),
    durationSec: meta?.length ? Math.round(meta.length) : null,
  });

  switch (update.kind) {
    case "ignore":
      return NextResponse.json({ ok: true, skipped: "already-settled" });
    case "processing":
      if (product.videoStatus !== "processing") {
        await prisma.product.update({
          where: { id: product.id },
          data: { videoStatus: "processing" },
        });
      }
      return NextResponse.json({ ok: true, encoded: "processing" });
    case "failed":
      await prisma.product.update({
        where: { id: product.id },
        data: { videoStatus: "failed" },
      });
      return NextResponse.json({ ok: true, encoded: "failed" });
    case "ready":
      await prisma.product.update({
        where: { id: product.id },
        data: {
          videoStatus: "ready",
          videoUrl: update.videoUrl,
          videoThumbnailUrl: update.videoThumbnailUrl,
          videoDurationSec: update.videoDurationSec,
        },
      });
      return NextResponse.json({ ok: true, encoded: "ready" });
  }
}
