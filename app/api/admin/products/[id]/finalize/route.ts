import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { finalizeCreatedProduct } from "@/lib/product/admin-product-form";
export async function POST(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) { if (!(await getSession("ADMIN"))) return NextResponse.json({ error: "Unauthorized" }, { status: 401 }); const product = await finalizeCreatedProduct((await params).id); if (!product) return NextResponse.json({ error: "Produk tidak dapat difinalisasi" }, { status: 409 }); return NextResponse.json({ ok: true, creationState: product.creationState }); }
