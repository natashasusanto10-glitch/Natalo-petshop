/**
 * Endpoint video produk (admin). Persist mandiri di luar submit form
 * Edit Produk karena alur provision→TUS→webhook bersifat async.
 *
 *   POST   → buat video di Bunny library produk, set videoGuid +
 *            videoStatus="uploading", balikan TUS credentials.
 *   PATCH  → tandai upload selesai → videoStatus="processing".
 *   DELETE → hapus video di Bunny + reset semua field video.
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import {
  createProductVideo,
  deleteProductVideo,
  generateProductTusCredentials,
  getProductBunnyConfig,
} from "@/lib/product/product-video";

export const dynamic = "force-dynamic";

function parseDuration(body: unknown): number | null {
  if (!body || typeof body !== "object") return null;
  const raw = (body as Record<string, unknown>).videoDurationSec;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrf = assertSameOrigin(request);
  if (csrf) return csrf;
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const cfg = getProductBunnyConfig();
  if (!cfg) {
    return NextResponse.json(
      { error: "Layanan video produk belum dikonfigurasi." },
      { status: 503 },
    );
  }
  // Body hanya bisa dibaca sekali — baca di awal, sebelum efek samping apa pun.
  const body = await request.json().catch(() => null);
  const duration = parseDuration(body);

  const { id } = await params;
  const product = await prisma.product.findUnique({
    where: { id },
    select: { id: true, videoGuid: true },
  });
  if (!product) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }

  // Provision video baru without deleting the existing Bunny asset. Cleanup is
  // deferred until the parent product save has succeeded (draft contract).

  const created = await createProductVideo({ title: `product-${product.id}` });
  if (!created || "error" in created) {
    return NextResponse.json(
      { error: created ? created.error : "Bunny tidak tersedia." },
      { status: 502 },
    );
  }
  const tus = await generateProductTusCredentials(created.guid);
  if (!tus) {
    // Bersihkan HANYA video baru yang gagal di-provision; video lama tetap utuh.
    await deleteProductVideo(created.guid);
    return NextResponse.json(
      { error: "Gagal menyiapkan kredensial upload." },
      { status: 502 },
    );
  }

  // Do not mutate product DB during draft provisioning. The parent form
  // attaches this guid only after its product save succeeds via PATCH.
  return NextResponse.json({ videoGuid: created.guid, tus, videoDurationSec: duration });
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrf = assertSameOrigin(request);
  if (csrf) return csrf;
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const body = await request.json().catch(() => null);
  const duration = parseDuration(body);
  const requestedGuid = body && typeof body === "object" ? (body as Record<string, unknown>).videoGuid : null;
  const product = await prisma.product.findUnique({
    where: { id },
    select: { id: true, videoGuid: true, videoStatus: true },
  });
  if (!product || (requestedGuid && typeof requestedGuid !== "string")) {
    return NextResponse.json(
      { error: "Belum ada video untuk produk ini." },
      { status: 404 },
    );
  }
  // Settled-guard: kalau webhook Bunny (FINISHED/failed) sudah lebih dulu
  // mendarat sebelum PATCH ini, jangan downgrade videoStatus balik ke
  // "processing" — produk bisa stuck tersembunyi walau videonya sudah siap.
  if (!requestedGuid) {
    return NextResponse.json({ error: "videoGuid wajib diisi setelah upload." }, { status: 400 });
  }
  if ((product.videoStatus === "ready" || product.videoStatus === "failed") && product.videoGuid === requestedGuid) {
    return NextResponse.json({ ok: true, skipped: "already-settled" });
  }
  await prisma.product.update({
    where: { id: product.id },
    data: {
      videoGuid: requestedGuid,
      videoStatus: "processing",
      ...(duration ? { videoDurationSec: duration } : {}),
    },
  });
  if (product.videoGuid && product.videoGuid !== requestedGuid) await deleteProductVideo(product.videoGuid);
  return NextResponse.json({ ok: true });
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrf = assertSameOrigin(request);
  if (csrf) return csrf;
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const body = await request.json().catch(() => null);
  const requestedGuid = body && typeof body === "object" ? (body as Record<string, unknown>).videoGuid : null;
  const product = await prisma.product.findUnique({
    where: { id },
    select: { id: true, videoGuid: true },
  });
  if (!product) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }
  const guidToDelete = typeof requestedGuid === "string" ? requestedGuid : product.videoGuid;
  if (guidToDelete) {
    await deleteProductVideo(guidToDelete);
  }
  if (requestedGuid && requestedGuid !== product.videoGuid) {
    return NextResponse.json({ ok: true, compensated: true });
  }
  await prisma.product.update({
    where: { id: product.id },
    data: {
      videoGuid: null,
      videoStatus: null,
      videoUrl: null,
      videoThumbnailUrl: null,
      videoDurationSec: null,
    },
  });
  return NextResponse.json({ ok: true });
}
