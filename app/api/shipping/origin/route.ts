import { NextResponse } from "next/server";
import {
  getOriginAreaId,
  logMissingOriginArea,
  ORIGIN_AREA_NOT_CONFIGURED_CODE,
  SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
} from "@/lib/shipping-origin";

export async function GET() {
  const originAreaId = getOriginAreaId();

  if (!originAreaId) {
    logMissingOriginArea();
    return NextResponse.json(
      {
        success: false,
        configured: false,
        code: ORIGIN_AREA_NOT_CONFIGURED_CODE,
        message: SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
      },
      { status: 503 },
    );
  }

  return NextResponse.json({ success: true, configured: true });
}
