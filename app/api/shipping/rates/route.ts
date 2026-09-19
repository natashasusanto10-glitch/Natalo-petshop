/**
 * POST /api/shipping/rates
 *
 * Body: {
 *   destinationAreaId: string,
 *   destinationPostalCode?: string,
 *   destinationLatitude?: number,
 *   destinationLongitude?: number,
 *   items: Array<{ name: string, price: number, weightGram: number, quantity: number }>
 * }
 *
 * Return: { rates: RateOption[] }
 *
 * Logika pengutipan tarif tinggal di lib/shipping-rates.ts — dipakai juga
 * /api/checkout/recalculate dan /api/orders supaya ongkir yang ditampilkan,
 * di-preview, dan ditagih selalu dari sumber yang sama. Endpoint ini cuma
 * membungkus hasilnya ke bentuk respons lama (klien dependen padanya).
 *
 * Catatan:
 *   - Filter has_cod/is_cod dari response (semua transaksi non-COD).
 *   - Field service_type dari Biteship dipakai untuk grouping di UI:
 *     instant | same_day | next_day | regular | economy | others
 */
import { NextResponse } from "next/server";
import {
  fetchShippingRateOptions,
  type ShippingItem,
} from "@/lib/shipping-rates";
import {
  logMissingOriginArea,
  ORIGIN_AREA_NOT_CONFIGURED_CODE,
  resolveOriginAreaId,
  SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
} from "@/lib/shipping-origin";

function numberOrNull(value: unknown) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

export async function POST(request: Request) {
  const body = await request.json();
  const originAreaId = await resolveOriginAreaId();

  if (!originAreaId) {
    logMissingOriginArea();
    return NextResponse.json(
      {
        success: false,
        code: ORIGIN_AREA_NOT_CONFIGURED_CODE,
        message: SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
        rates: [],
      },
      { status: 503 }
    );
  }

  const items: ShippingItem[] = Array.isArray(body.items) ? body.items : [];

  const result = await fetchShippingRateOptions({
    originAreaId,
    destinationAreaId:
      typeof body.destinationAreaId === "string"
        ? body.destinationAreaId.trim()
        : null,
    destinationPostalCode:
      typeof body.destinationPostalCode === "string"
        ? body.destinationPostalCode.trim()
        : null,
    destinationLatitude: numberOrNull(body.destinationLatitude),
    destinationLongitude: numberOrNull(body.destinationLongitude),
    items,
  });

  if (!result.ok) {
    switch (result.reason) {
      case "ITEMS_EMPTY":
        return NextResponse.json(
          { message: result.message },
          { status: 400 }
        );
      case "INVALID_DESTINATION":
        return NextResponse.json(
          { message: result.message },
          { status: 400 }
        );
      case "BITESHIP_HTTP":
        return NextResponse.json(
          { message: result.message, rates: [] },
          { status: 400 }
        );
      case "BITESHIP_NETWORK":
        return NextResponse.json(
          { message: result.message, rates: [] },
          { status: 500 }
        );
      case "ORIGIN_NOT_CONFIGURED":
        return NextResponse.json(
          {
            success: false,
            code: ORIGIN_AREA_NOT_CONFIGURED_CODE,
            message: result.message,
            rates: [],
          },
          { status: 503 }
        );
    }
  }

  // Mode dummy/flat → respons membawa `message`; mode Biteship →
  // `instantUnavailableReason`. Bentuk persis seperti sebelum refactor.
  if (result.message !== undefined) {
    return NextResponse.json({
      rates: result.rates,
      message: result.message,
    });
  }
  return NextResponse.json({
    rates: result.rates,
    instantUnavailableReason: result.instantUnavailableReason,
  });
}
