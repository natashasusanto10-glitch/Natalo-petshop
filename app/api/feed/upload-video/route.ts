/**
 * POST /api/feed/upload-video
 *
 * Multipart upload untuk video user (kind=COMMUNITY) atau admin (kind=VIDEO_*).
 * Validasi sebelum push ke UploadThing:
 * - MIME wajib video/mp4 | video/webm | video/quicktime
 * - Size max 10 MB untuk user community, 25 MB untuk admin. Client compress
 *   raw video sebelum sampai endpoint ini.
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
import { ADMIN_VIDEO_CONFIG, USER_VIDEO_CONFIG, formatFileSize } from "@/lib/feed/video-config";

const ALLOWED_TYPES = new Set([
  "video/mp4",
  "video/webm",
  "video/quicktime", // iOS .mov
]);
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
  const maxSize =
    session.role === "ADMIN" ? ADMIN_VIDEO_CONFIG.maxFileSize : USER_VIDEO_CONFIG.maxFileSize;
  if (file.size > maxSize) {
    return NextResponse.json(
      { error: `Ukuran video maksimal ${formatFileSize(maxSize)} setelah kompresi.` },
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
