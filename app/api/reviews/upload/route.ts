import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { uploadToUT } from "@/lib/uploadthing";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";

const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const ALLOWED_VIDEO_TYPES = new Set([
  "video/mp4",
  "video/webm",
  "video/quicktime",
]);
const MAX_IMAGE_SIZE = 5 * 1024 * 1024;
const MAX_VIDEO_SIZE = 25 * 1024 * 1024;

export async function POST(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;

  if (!file) {
    return NextResponse.json(
      { error: "File tidak ditemukan" },
      { status: 400 }
    );
  }
  const isImage = ALLOWED_IMAGE_TYPES.has(file.type);
  const isVideo = ALLOWED_VIDEO_TYPES.has(file.type);

  if (!isImage && !isVideo) {
    return NextResponse.json(
      { error: "Format harus JPG, PNG, WEBP, MP4, WEBM, atau MOV" },
      { status: 400 }
    );
  }
  const maxSize = isVideo ? MAX_VIDEO_SIZE : MAX_IMAGE_SIZE;
  if (file.size > maxSize) {
    return NextResponse.json(
      {
        error: isVideo
          ? "Ukuran video maksimal 25 MB"
          : "Ukuran foto maksimal 5 MB",
      },
      { status: 400 }
    );
  }

  const buffer = Buffer.from(await file.arrayBuffer());
  // Magic-byte check untuk image — cegah polyglot/SVG-XSS payload yang spoof Content-Type.
  // Video container header lebih bervariasi (.mp4/.mov/webm), validasi MIME + size cukup di endpoint ini.
  if (isImage && !validateImageMagicBytes(buffer, file.type)) {
    return NextResponse.json(
      { error: "Isi file tidak cocok dengan format gambar" },
      { status: 415 }
    );
  }

  try {
    const { url } = await uploadToUT(file, isVideo ? "review-video" : "review");
    return NextResponse.json({
      url,
      mediaType: isVideo ? "video" : "image",
      mimeType: file.type,
      sizeBytes: file.size,
    });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "Upload gagal" },
      { status: 500 }
    );
  }
}
