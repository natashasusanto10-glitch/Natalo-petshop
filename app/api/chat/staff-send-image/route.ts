/**
 * POST /api/chat/staff-send-image
 *
 * Jembatan UploadThing stateless untuk staff (NLCATTER) mengirim foto ke
 * chat customer. Endpoint ini HANYA mengunggah gambar dan mengembalikan
 * {url} — penulisan pesan type:'image' ke Firestore dilakukan oleh
 * NLCATTER sendiri (Plan 5), bukan di sini.
 *
 * Auth: ID token staff (verifyStaffRequest), BUKAN sesi customer.
 * Tanpa CSRF (assertSameOrigin) — klien native, bukan browser; keamanan
 * berasal dari verifikasi token.
 *
 * Validasi (mirror app/api/feed/upload-photo/route.ts):
 * - MIME image/jpeg | image/png | image/webp
 * - Size max 8 MB
 * - Magic-byte check (defense in depth)
 *
 * Response:
 *   { url: string }   — UploadThing CDN url (tanpa key)
 */
import { NextRequest, NextResponse } from "next/server";
import { verifyStaffRequest } from "@/lib/chat/staff-auth";
import { isChatEnabled } from "@/app/api/chat/config/route";
import { uploadToUT } from "@/lib/uploadthing";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_SIZE = 8 * 1024 * 1024; // 8 MB

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  const auth = await verifyStaffRequest(request);
  if (auth instanceof NextResponse) return auth;

  // Kill-switch (fix C1) — simetris dengan endpoint customer Plan 2;
  // jangan biarkan staff kirim foto ke chat saat chat mati.
  if (!(await isChatEnabled())) {
    return NextResponse.json({ error: "Chat sedang nonaktif." }, { status: 503 });
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
    const { url } = await uploadToUT(file, `custchat-${auth.uid}`);
    return NextResponse.json({ url });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Upload gagal" },
      { status: 500 },
    );
  }
}
