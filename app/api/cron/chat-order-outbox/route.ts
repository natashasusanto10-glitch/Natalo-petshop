import { NextRequest, NextResponse } from "next/server";
import { assertCronAuth } from "@/lib/cron-auth";
import { processOrderContextOutboxBatch } from "@/lib/chat/order-outbox";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: NextRequest) {
  const unauthorized = assertCronAuth(request);
  if (unauthorized) return unauthorized;
  const result = await processOrderContextOutboxBatch();
  return NextResponse.json(result, { headers: { "Cache-Control": "private, no-store" } });
}
