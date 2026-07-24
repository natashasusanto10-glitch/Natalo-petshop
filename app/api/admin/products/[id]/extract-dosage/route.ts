import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { extractDosageRulesFromText, ExtractDosageError } from "@/lib/ai/extract-dosage-rules";

/**
 * POST /api/admin/products/{id}/extract-dosage
 *
 * Ekstrak aturan dosis obat cacing/kutu dari nama+deskripsi produk via AI.
 * Hanya mengembalikan draft (DosageRule[]) — TIDAK menulis ke database.
 * Admin yang menyimpan setelah review manual di form produk.
 *
 * Body: { name: string, description: string }
 */
export async function POST(
  request: Request,
  _ctx: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const body = await request.json().catch(() => null);
  const name = typeof body?.name === "string" ? body.name : "";
  const description = typeof body?.description === "string" ? body.description : "";
  if (!name.trim() || !description.trim()) {
    return NextResponse.json({ error: "Nama dan deskripsi wajib diisi." }, { status: 400 });
  }
  try {
    const dosageRules = await extractDosageRulesFromText({ name, description });
    return NextResponse.json({ dosageRules });
  } catch (err) {
    if (err instanceof ExtractDosageError) {
      return NextResponse.json({ error: err.message, code: err.code }, { status: 502 });
    }
    return NextResponse.json({ error: "Gagal ekstrak dosis." }, { status: 500 });
  }
}
