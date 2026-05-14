import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { uploadToUT } from "@/lib/uploadthing";
import { getSession } from "@/lib/auth";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_SIZE = 5 * 1024 * 1024;

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  const { orderNumber } = await params;

  const order = await prisma.order
    .findUnique({ where: { orderNumber } })
    .catch(() => null);
  if (!order) {
    return NextResponse.json({ error: "Order tidak ditemukan" }, { status: 404 });
  }

  // ── Authorization — pattern sama dgn GET /pesanan/[orderNumber] di
  //   app/pesanan/[orderNumber]/page.tsx. User boleh upload bukti
  //   pembayaran HANYA kalau:
  //   1. Logged-in member yang own order (session.sub === order.userId), ATAU
  //   2. Akses via tracking link valid (?token=<order.trackingToken>) — untuk
  //      guest order yang tidak login.
  //
  //   Sebelumnya endpoint ini OPEN — siapapun bisa overwrite paymentProofUrl
  //   order user lain + spam upload 5MB ke UploadThing (cost + IDOR).
  const token = new URL(request.url).searchParams.get("token");
  const session = await getSession("CUSTOMER").catch(() => null);
  const isOwner = Boolean(session?.sub && order.userId === session.sub);
  const hasValidToken = Boolean(
    token && order.trackingToken && token === order.trackingToken,
  );
  if (!isOwner && !hasValidToken) {
    return NextResponse.json(
      { error: "Tidak punya akses ke order ini" },
      { status: 403 },
    );
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;

  if (!file) return NextResponse.json({ error: "File wajib diunggah" }, { status: 400 });
  if (!ALLOWED_TYPES.has(file.type)) {
    return NextResponse.json({ error: "Format harus JPG, PNG, atau WEBP" }, { status: 400 });
  }
  if (file.size > MAX_SIZE) {
    return NextResponse.json({ error: "Ukuran file maksimal 5 MB" }, { status: 400 });
  }

  // Magic-byte check — cegah polyglot/SVG-XSS payload dgn Content-Type
  // spoofed sebagai image/jpeg. Admin akan view proof di /admin/pickup-validation;
  // tanpa check ini, attacker bisa inject script via UploadThing trusted origin.
  const buffer = Buffer.from(await file.arrayBuffer());
  if (!validateImageMagicBytes(buffer, file.type)) {
    return NextResponse.json(
      { error: "Isi file tidak cocok dengan format gambar" },
      { status: 415 },
    );
  }

  try {
    const { url } = await uploadToUT(file, `proof-${orderNumber}`);
    await prisma.order.update({
      where: { orderNumber },
      data: { paymentProofUrl: url },
    });
    return NextResponse.json({ url });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "Upload gagal" },
      { status: 500 },
    );
  }
}
