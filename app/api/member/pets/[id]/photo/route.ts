/**
 * POST /api/member/pets/{id}/photo
 *
 * Upload foto pet. Pakai UploadThing (infrastruktur sama dengan foto
 * profil member — lihat app/api/auth/me/photo/route.ts).
 *
 * Request: multipart/form-data dengan field `file`.
 * Response: `{ ok: true, url, pet }`.
 *
 * Validasi sama dengan foto profil: MIME jpeg/png/webp, max 5 MB, magic
 * byte check.
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { uploadToUT } from "@/lib/uploadthing";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_SIZE = 5 * 1024 * 1024;

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Login member dulu." }, { status: 401 });
  }

  const { id } = await params;
  const existing = await prisma.pet.findFirst({
    where: { id, userId: session.sub },
  });
  if (!existing) {
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;

  if (!file) {
    return NextResponse.json({ error: "Foto wajib di-upload." }, { status: 400 });
  }
  if (!ALLOWED_TYPES.has(file.type)) {
    return NextResponse.json(
      { error: "Format foto harus JPG, PNG, atau WebP." },
      { status: 400 },
    );
  }
  if (file.size > MAX_SIZE) {
    return NextResponse.json({ error: "Foto maksimal 5 MB." }, { status: 413 });
  }

  const buffer = Buffer.from(await file.arrayBuffer());
  const validMagic = validateImageMagicBytes(buffer, file.type);
  if (!validMagic) {
    return NextResponse.json({ error: "File foto tidak valid." }, { status: 400 });
  }

  try {
    const renamed = new File(
      [buffer],
      `pet-${id}-${Date.now()}.${file.type.split("/")[1]}`,
      { type: file.type },
    );
    const upload = await uploadToUT(renamed, "pet");

    const pet = await prisma.pet.update({
      where: { id },
      data: { photoUrl: upload.url },
    });

    return NextResponse.json({ ok: true, url: upload.url, pet });
  } catch (error) {
    console.error("[member/pets/photo] upload error:", error);
    return NextResponse.json(
      { error: "Upload foto gagal. Coba lagi sebentar." },
      { status: 500 },
    );
  }
}
