/**
 * POST /api/auth/me/photo
 *
 * Upload foto profil member. Pakai UploadThing (existing infrastructure
 * yang udah dipakai untuk feed thumbnail + review photo).
 *
 * Request: multipart/form-data dengan field `file`.
 * Response: `{ ok: true, url, user }` — URL CDN siap dipakai.
 *
 * Setelah upload sukses, langsung update User.profilePhotoUrl di DB
 * supaya bisa langsung ke-pickup di GET /api/auth/me + feed queries.
 *
 * Validasi:
 * - MIME image/jpeg | image/png | image/webp
 * - Size max 5 MB (foto profil tidak butuh besar — UploadThing free tier
 *   limit 4 MB, kasih 5 MB sebagai upper bound dengan error friendly)
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { uploadToUT } from "@/lib/uploadthing";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_SIZE = 5 * 1024 * 1024;

export async function POST(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json(
      { error: "Login member dulu." },
      { status: 401 },
    );
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;

  if (!file) {
    return NextResponse.json(
      { error: "Foto wajib di-upload." },
      { status: 400 },
    );
  }
  if (!ALLOWED_TYPES.has(file.type)) {
    return NextResponse.json(
      { error: "Format foto harus JPG, PNG, atau WebP." },
      { status: 400 },
    );
  }
  if (file.size > MAX_SIZE) {
    return NextResponse.json(
      { error: "Foto maksimal 5 MB." },
      { status: 413 },
    );
  }

  // Defense in depth — magic byte check, anti file dengan ekstensi /
  // MIME palsu (mis. rename .exe ke .jpg).
  const buffer = Buffer.from(await file.arrayBuffer());
  const validMagic = validateImageMagicBytes(buffer, file.type);
  if (!validMagic) {
    return NextResponse.json(
      { error: "File foto tidak valid." },
      { status: 400 },
    );
  }

  try {
    // Upload ke UploadThing CDN — return signed URL.
    const renamed = new File(
      [buffer],
      `avatar-${session.sub}-${Date.now()}.${file.type.split("/")[1]}`,
      { type: file.type },
    );
    const upload = await uploadToUT(renamed, "avatar");

    // Save URL ke User.profilePhotoUrl. Replace existing (UploadThing
    // file lama akan jadi orphan — bisa di-cleanup via cron job nanti,
    // atau just leave it karena cost storage marginal).
    const user = await prisma.user.update({
      where: { id: session.sub },
      data: { profilePhotoUrl: upload.url },
      select: {
        id: true,
        name: true,
        email: true,
        phone: true,
        birthDate: true,
        createdAt: true,
        profilePhotoUrl: true,
      },
    });

    return NextResponse.json({
      ok: true,
      url: upload.url,
      user,
    });
  } catch (error) {
    console.error("[auth/me/photo] upload error:", error);
    return NextResponse.json(
      { error: "Upload foto gagal. Coba lagi sebentar." },
      { status: 500 },
    );
  }
}

/**
 * DELETE /api/auth/me/photo
 *
 * Hapus foto profil — set profilePhotoUrl ke null. UploadThing file
 * di-orphan (cleanup via cron). UI akan fallback ke initial avatar.
 */
export async function DELETE() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json(
      { error: "Login member dulu." },
      { status: 401 },
    );
  }

  await prisma.user.update({
    where: { id: session.sub },
    data: { profilePhotoUrl: null },
  });

  return NextResponse.json({ ok: true });
}
