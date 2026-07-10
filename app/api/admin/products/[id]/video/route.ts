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

  // Ganti video: create-before-delete. Provision video BARU dulu, baru
  // repoint DB, baru bersihkan video LAMA (best-effort). Kalau create atau
  // TUS gagal (transient), video lama yang masih berfungsi tidak ikut hilang —
  // DB tidak disentuh sampai video baru benar-benar siap dipakai.
  const oldGuid = product.videoGuid;

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

  await prisma.product.update({
    where: { id: product.id },
    data: {
      videoGuid: created.guid,
      videoStatus: "uploading",
      videoDurationSec: duration,
      videoUrl: null,
      videoThumbnailUrl: null,
    },
  });

  // DB sudah repoint ke video baru — video lama kini tidak lagi direferensikan,
  // aman dihapus (best-effort; cron GC jadi backstop kalau ini gagal).
  if (oldGuid && oldGuid !== created.guid) {
    await deleteProductVideo(oldGuid);
  }

  return NextResponse.json({ videoGuid: created.guid, tus });
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
  const product = await prisma.product.findUnique({
    where: { id },
    select: { id: true, videoGuid: true, videoStatus: true },
  });
  if (!product?.videoGuid) {
    return NextResponse.json(
      { error: "Belum ada video untuk produk ini." },
      { status: 404 },
    );
  }
  // Settled-guard: kalau webhook Bunny (FINISHED/failed) sudah lebih dulu
  // mendarat sebelum PATCH ini, jangan downgrade videoStatus balik ke
  // "processing" — produk bisa stuck tersembunyi walau videonya sudah siap.
  if (product.videoStatus === "ready" || product.videoStatus === "failed") {
    return NextResponse.json({ ok: true, skipped: "already-settled" });
  }
  await prisma.product.update({
    where: { id: product.id },
    data: {
      videoStatus: "processing",
      ...(duration ? { videoDurationSec: duration } : {}),
    },
  });
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
  const product = await prisma.product.findUnique({
    where: { id },
    select: { id: true, videoGuid: true },
  });
  if (!product) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }
  if (product.videoGuid) {
    await deleteProductVideo(product.videoGuid);
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
