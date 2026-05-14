/**
 * POST /api/feed/upload-thumbnail
 *
 * Image upload untuk thumbnail video. Pattern: client extract frame
 * via Canvas API saat user pick video, upload JPEG di-sini, lalu
 * pass URL ke POST /api/feed/posts.
 *
 * Validasi:
 * - MIME image/jpeg | image/png | image/webp
 * - Size max 1 MB (thumbnail kecil, defensif)
 * - Magic-byte check (defense in depth, sama dgn admin/upload)
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { uploadToUT } from "@/lib/uploadthing";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_SIZE = 1 * 1024 * 1024; // 1 MB

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Login dulu." }, { status: 401 });
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;

  if (!file) {
    return NextResponse.json({ error: "Thumbnail wajib." }, { status: 400 });
  }
  if (!ALLOWED_TYPES.has(file.type)) {
    return NextResponse.json(
      { error: "Format thumbnail harus JPG, PNG, atau WebP." },
      { status: 400 },
    );
  }
  if (file.size > MAX_SIZE) {
    return NextResponse.json(
      { error: "Thumbnail maksimal 1 MB." },
      { status: 413 },
    );
  }

  const buffer = Buffer.from(await file.arrayBuffer());
  if (!validateImageMagicBytes(buffer, file.type)) {
    return NextResponse.json(
      { error: "Isi thumbnail tidak cocok dengan format gambar." },
      { status: 415 },
    );
  }

  try {
    const { url, key } = await uploadToUT(file, `feed-thumb-${session.sub}`);
    return NextResponse.json({ url, key });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Upload gagal" },
      { status: 500 },
    );
  }
}
