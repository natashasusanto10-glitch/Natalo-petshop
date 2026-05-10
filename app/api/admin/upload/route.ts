import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";
import { uploadToUT } from "@/lib/uploadthing";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const MAX_SIZE = 2 * 1024 * 1024;

export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;

  if (!file) {
    return NextResponse.json({ error: "File tidak ditemukan" }, { status: 400 });
  }

  if (!ALLOWED_TYPES.has(file.type)) {
    return NextResponse.json(
      { error: "Format harus JPG, PNG, WEBP, atau GIF" },
      { status: 400 }
    );
  }

  if (file.size > MAX_SIZE) {
    return NextResponse.json({ error: "Ukuran file maksimal 2 MB" }, { status: 400 });
  }

  const buffer = Buffer.from(await file.arrayBuffer());
  if (!validateImageMagicBytes(buffer, file.type)) {
    return NextResponse.json(
      { error: "Isi file tidak cocok dengan format gambar" },
      { status: 415 }
    );
  }

  try {
    const { url } = await uploadToUT(file, "product");
    return NextResponse.json({ url });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "Upload gagal" },
      { status: 500 }
    );
  }
}
