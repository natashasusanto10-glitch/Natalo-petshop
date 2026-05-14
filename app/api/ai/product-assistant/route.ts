import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { checkLimit, getAiLimiter } from "@/lib/rate-limit";

const MAX_QUESTION_LENGTH = 500;
const MAX_PRODUCTS_CONTEXT = 30;

export async function POST(request: NextRequest) {
  // Wajib login
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Login diperlukan" }, { status: 401 });
  }

  // Rate limit per-user (key = userId, bukan IP) — cegah OpenAI budget burn
  // dari 1 user yang loop POST. 20 calls/jam = ~3 menit cooldown per call,
  // cukup untuk UX tanya jawab normal.
  const gate = await checkLimit(getAiLimiter(), `ai-assistant:${session.sub}`);
  if (!gate.ok) {
    return NextResponse.json(
      { error: "Kamu sudah banyak bertanya hari ini. Coba lagi nanti." },
      { status: 429, headers: { "Retry-After": String(gate.retryAfter) } },
    );
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return NextResponse.json({
      answer: "Fitur asisten produk belum aktif. Hubungi admin untuk informasi produk.",
    });
  }

  const body = await request.json();
  const question = String(body.question || "").trim().slice(0, MAX_QUESTION_LENGTH);

  if (!question) {
    return NextResponse.json({ error: "Pertanyaan tidak boleh kosong" }, { status: 400 });
  }

  // Ambil produk aktif terbatas — produk terpopuler saja, bukan semua katalog
  const products = await prisma.product.findMany({
    where: { isActive: true, stock: { gt: 0 } },
    select: {
      name: true,
      price: true,
      stock: true,
      category: { select: { name: true } },
    },
    orderBy: { reviewCount: "desc" },
    take: MAX_PRODUCTS_CONTEXT,
  });

  const client = new OpenAI({ apiKey });
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  const productContext = products
    .map((p) => `- ${p.name} (${p.category?.name ?? "Umum"}): Rp${p.price.toLocaleString("id-ID")}, stok ${p.stock}`)
    .join("\n");

  try {
    const completion = await client.chat.completions.create({
      model,
      messages: [
        {
          role: "system",
          content:
            "Kamu adalah product assistant untuk Natalo Petshop. Jawab dalam Bahasa Indonesia, ramah, ringkas, dan hanya rekomendasikan produk yang ada di katalog. Jangan memberi klaim medis atau janji berlebihan.",
        },
        {
          role: "user",
          content: `Katalog produk populer:\n${productContext}\n\nPertanyaan: ${question}`,
        },
      ],
      max_tokens: 500,
    });

    return NextResponse.json({ answer: completion.choices[0]?.message?.content ?? "" });
  } catch {
    return NextResponse.json({ error: "Gagal mendapatkan jawaban. Coba lagi." }, { status: 500 });
  }
}
