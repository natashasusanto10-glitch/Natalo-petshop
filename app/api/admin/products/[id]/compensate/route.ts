import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { compensateCreatedProduct } from "@/lib/product/admin-product-form";
export async function POST(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) { if (!(await getSession("ADMIN"))) return NextResponse.json({ error: "Unauthorized" }, { status: 401 }); return NextResponse.json({ compensated: await compensateCreatedProduct((await params).id) }); }
