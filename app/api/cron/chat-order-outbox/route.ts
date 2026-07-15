import { NextRequest, NextResponse } from "next/server";
import { processOrderContextOutboxBatch } from "@/lib/chat/order-outbox";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: NextRequest) {
  const expected = process.env.CRON_SECRET;
  if (!expected || request.headers.get("authorization") !== `Bearer ${expected}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const result = await processOrderContextOutboxBatch();
  return NextResponse.json(result, { headers: { "Cache-Control": "private, no-store" } });
}
