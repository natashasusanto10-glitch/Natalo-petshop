import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { generateProductDescription, GenerateDescriptionError } from "@/lib/ai/generate-product-description";
import { buildDescriptionContext } from "@/lib/ai/product-description-context";

export async function POST(request: NextRequest) {
  if (!(await getSession("ADMIN"))) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const body = await request.json().catch(() => ({}));
  const context = buildDescriptionContext({
    name: typeof body.name === "string" ? body.name : "",
    categoryName: body.categoryName,
    brandName: body.brandName,
    variants: Array.isArray(body.variants) ? body.variants : [],
  });
  try {
    return NextResponse.json({ description: await generateProductDescription(context) });
  } catch (err) {
    if (err instanceof GenerateDescriptionError) {
      return NextResponse.json({ error: err.message }, { status: err.code === "INVALID_INPUT" || err.code === "MISSING_KEY" ? 400 : 502 });
    }
    return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 500 });
  }
}
