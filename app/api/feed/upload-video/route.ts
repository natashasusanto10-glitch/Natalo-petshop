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
import { prisma } from "@/lib/prisma";
import { ADMIN_VIDEO_CONFIG, USER_VIDEO_CONFIG, formatFileSize } from "@/lib/feed/video-config";

const ALLOWED_TYPES = new Set([
  "video/mp4",
  "video/webm",
  "video/quicktime", // iOS .mov
]);

// Customer-side feed VIDEO upload limit. Counts ONLY video FeedPost rows
// (VIDEO_ONLY + COMMUNITY) created in the last 24h by the same user,
// regardless of moderation status — so a flood of upload→reject loops still
// counts. Photo carousel posts (PHOTO_CAROUSEL) are unlimited dan TIDAK
// di-count di sini supaya heavy photo poster tidak ikut nge-block video
// upload slot. Admins exempt.
const CUSTOMER_RATE_LIMIT_PER_DAY = 10;
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;
export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  // Try ADMIN first supaya admin yang upload tidak mis-detect as customer
  // (legacy bug: getSession() default priority MEMBER cookie kalau admin
  // juga punya member cookie). Lihat lib/auth.ts:66.
  const session =
    (await getSession("ADMIN")) ?? (await getSession("CUSTOMER"));
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

  // Customer rate limit: max 10 VIDEO uploads / 24h. Admins exempt — they
  // post promo and curated content. Count over VIDEO_ONLY + COMMUNITY kinds
  // saja (exclude PHOTO_CAROUSEL — photo unlimited per product decision).
  // Tanpa filter kind, heavy photo poster akan ikut burn video slot meski
  // belum upload video sekalipun = bad UX.
  if (session.role !== "ADMIN") {
    const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MS);
    const recentCount = await prisma.feedPost.count({
      where: {
        authorId: session.sub,
        createdAt: { gte: since },
        kind: { in: ["VIDEO_ONLY", "COMMUNITY"] },
      },
    });
    if (recentCount >= CUSTOMER_RATE_LIMIT_PER_DAY) {
      return NextResponse.json(
        {
          error: `Batas upload video tercapai (${CUSTOMER_RATE_LIMIT_PER_DAY}/hari). Coba lagi besok atau post foto.`,
        },
        { status: 429 },
      );
    }
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
