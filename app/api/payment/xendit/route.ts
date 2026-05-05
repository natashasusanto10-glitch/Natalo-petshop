import { NextResponse } from "next/server";

export async function POST() {
  return NextResponse.json({
    message: "Payment Xendit dibuat dari /api/orders agar order dan payment tetap sinkron. Endpoint ini placeholder untuk webhook/callback handler.",
  });
}
