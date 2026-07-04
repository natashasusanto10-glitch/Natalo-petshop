import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";
import { normalizeBrandLogo } from "@/lib/upload/normalize-logo";
import { uploadToUT } from "@/lib/uploadthing";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const MAX_SIZE = 2 * 1024 * 1024;

export type UploadKind = "product" | "brand-logo";

export function resolveUploadKind(rawKind: FormDataEntryValue | null): UploadKind {
  return rawKind === "brand-logo" ? "brand-logo" : "product";
}

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;
  const kind = resolveUploadKind(formData.get("kind"));

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
    let uploadFile: File;
    if (kind === "brand-logo") {
      const normalized = await normalizeBrandLogo(buffer);
      // Buffer (ArrayBufferLike) tidak assignable ke BlobPart di TS strict
      // (bisa SharedArrayBuffer). Salin ke Uint8Array ber-ArrayBuffer bersih
      // supaya File() menerimanya — kalau tidak, `next build` gagal
      // type-check dan SELURUH deploy Vercel merah.
      uploadFile = new File(
        [new Uint8Array(normalized)],
        file.name.replace(/\.\w+$/, ".png"),
        { type: "image/png" },
      );
    } else {
      uploadFile = file;
    }
    const { url } = await uploadToUT(uploadFile, kind === "brand-logo" ? "brand-logo" : "product");
    return NextResponse.json({ url });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "Upload gagal" },
      { status: 500 }
    );
  }
}
