/**
 * POST /api/feed/upload-photo
 *
 * Image upload untuk Feed PHOTO_CAROUSEL post (1-8 foto per post).
 * Pattern: client (Flutter) upload satu foto per request, batch
 * paralel 1-8x. Server return {url, key} per upload — client kumpulkan
 * URLs lalu pass ke POST /api/feed/posts dengan kind=PHOTO_CAROUSEL.
 *
 * Validasi:
 * - MIME image/jpeg | image/png | image/webp
 * - Size max 8 MB per foto (lebih longgar dari thumbnail 1 MB karena
 *   foto utama ditampilkan full-screen di feed, butuh resolusi lebih).
 * - Magic-byte check (defense in depth)
 *
 * Response:
 *   { url: string, key: string }   — UploadThing CDN url + key
 *   { width?: number, height?: number }  — TODO: parse via sharp/probe
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { uploadToUT } from "@/lib/uploadthing";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_SIZE = 8 * 1024 * 1024; // 8 MB per foto

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
    return NextResponse.json(
      { error: "Foto wajib." },
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
      { error: "Foto maksimal 8 MB." },
      { status: 413 },
    );
  }

  const buffer = Buffer.from(await file.arrayBuffer());
  if (!validateImageMagicBytes(buffer, file.type)) {
    return NextResponse.json(
      { error: "Isi foto tidak cocok dengan format gambar." },
      { status: 415 },
    );
  }

  try {
    const { url, key } = await uploadToUT(file, `feed-photo-${session.sub}`);
    return NextResponse.json({ url, key });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Upload gagal" },
      { status: 500 },
    );
  }
}
