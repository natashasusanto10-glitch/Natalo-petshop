/**
 * POST /api/feed/upload-video
 *
 * Multipart upload untuk video user (kind=COMMUNITY) atau admin (kind=VIDEO_*).
 * Validasi sebelum push ke UploadThing:
 * - MIME wajib video/mp4 | video/webm | video/quicktime
 * - Size max 30 MB (hard limit — UploadThing 100GB cukup, tapi kita kontrol
 *   bandwidth + storage growth. Spec 10.5 sebut 100-200 MB, tapi tanpa
 *   server-side transcode kita conservative biar feed tetap ringan)
 * - Magic-byte cek skip dulu — video format header varied (ftyp, mvhd,
 *   matroska box dll), tambahkan kalau abuse pattern muncul
 *
 * Response: { videoUrl, sizeBytes, mimeType }
 * Caller (upload form) extract thumbnail client-side via Canvas, upload
 * thumbnail terpisah via /api/feed/upload-thumbnail, lalu submit post via
 * POST /api/feed/posts dgn kedua URL.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { uploadToUT } from "@/lib/uploadthing";

const ALLOWED_TYPES = new Set([
  "video/mp4",
  "video/webm",
  "video/quicktime", // iOS .mov
]);
const MAX_SIZE = 30 * 1024 * 1024; // 30 MB

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Login dulu untuk upload video." }, { status: 401 });
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;

  if (!file) {
    return NextResponse.json({ error: "File video wajib diunggah." }, { status: 400 });
  }
  if (!ALLOWED_TYPES.has(file.type)) {
    return NextResponse.json(
      { error: "Format harus MP4, WebM, atau MOV." },
      { status: 400 },
    );
  }
  if (file.size > MAX_SIZE) {
    return NextResponse.json(
      { error: "Ukuran video maksimal 30 MB. Rekam video lebih pendek atau kompres dulu." },
      { status: 413 },
    );
  }

  try {
    const { url, key } = await uploadToUT(file, `feed-video-${session.sub}`);
    return NextResponse.json({
      url,
      key,
      sizeBytes: file.size,
      mimeType: file.type,
    });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Upload gagal" },
      { status: 500 },
    );
  }
}
