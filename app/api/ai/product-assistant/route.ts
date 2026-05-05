import { NextResponse } from "next/server";
import OpenAI from "openai";
import { getProducts } from "@/lib/products";

export async function POST(request: Request) {
  const { question } = await request.json();
  const products = await getProducts();
  const apiKey = process.env.OPENAI_API_KEY;

  if (!apiKey) {
    return NextResponse.json({
      answer: "OPENAI_API_KEY belum diisi. Setelah API key aktif, saya bisa menjawab rekomendasi produk berdasarkan katalog.",
    });
  }

  const client = new OpenAI({ apiKey });
  const model = process.env.OPENAI_MODEL || "gpt-5.5";

  const productContext = products.map((p) => `- ${p.name}: harga ${p.memberPrice ?? p.price}, stok ${p.stock}, deskripsi: ${p.description}`).join("\n");

  const response = await client.responses.create({
    model,
    input: [
      {
        role: "system",
        content: "Kamu adalah product assistant untuk website toko online resmi. Jawab dalam Bahasa Indonesia, ramah, ringkas, dan hanya rekomendasikan produk yang ada di katalog. Jangan memberi klaim medis atau janji berlebihan.",
      },
      {
        role: "user",
        content: `Katalog produk:\n${productContext}\n\nPertanyaan customer: ${question}`,
      },
    ],
  });

  return NextResponse.json({ answer: response.output_text });
}
