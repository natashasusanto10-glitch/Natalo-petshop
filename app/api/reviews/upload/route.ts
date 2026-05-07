/**
 * POST /api/reviews/upload — upload foto review (customer auth required)
 */
import { NextRequest, NextResponse } from "next/server";
import { writeFile } from "fs/promises";
import path from "path";
import { randomBytes } from "crypto";
import { getSession } from "@/lib/auth";

const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"];
const MAX_SIZE = 5 * 1024 * 1024; // 5 MB

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session)
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });

  const formData = await request.formData();
  const file = formData.get("file") as File | null;

  if (!file)
    return NextResponse.json({ error: "File tidak ditemukan" }, { status: 400 });

  if (!ALLOWED_TYPES.includes(file.type))
    return NextResponse.json(
      { error: "Format harus JPG, PNG, atau WEBP" },
      { status: 400 }
    );

  if (file.size > MAX_SIZE)
    return NextResponse.json(
      { error: "Ukuran file maksimal 5 MB" },
      { status: 400 }
    );

  const ext = file.name.split(".").pop()?.toLowerCase() || "jpg";
  const filename = `review-${Date.now()}-${randomBytes(6).toString("hex")}.${ext}`;
  const filepath = path.join(process.cwd(), "public", "uploads", "reviews", filename);

  // Ensure directory exists
  const dir = path.dirname(filepath);
  const { mkdir } = await import("fs/promises");
  await mkdir(dir, { recursive: true });

  const buffer = Buffer.from(await file.arrayBuffer());
  await writeFile(filepath, buffer);

  return NextResponse.json({ url: `/uploads/reviews/${filename}` });
}
