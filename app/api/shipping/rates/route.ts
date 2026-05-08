/**
 * POST /api/shipping/rates
 *
 * Body: {
 *   destinationPostalCode: string,
 *   destinationLatitude?: number,
 *   destinationLongitude?: number,
 *   items: Array<{ name: string, price: number, weightGram: number, quantity: number }>
 * }
 *
 * Return: { rates: RateOption[] }
 *
 * Catatan:
 *   - Filter has_cod/is_cod dari response (semua transaksi non-COD).
 *   - Field service_type dari Biteship dipakai untuk grouping di UI:
 *     instant | same_day | next_day | regular | economy | others
 */
import { NextResponse } from "next/server";

export type ShippingItem = {
  name: string;
  price: number;
  weightGram: number;
  quantity: number;
};

export type RateOption = {
  courier_name: string;
  courier_code: string;
  courier_service_name: string;
  courier_service_code: string;
  service_type: string;
  price: number;
  duration: string;
  available: boolean;
  unavailable_reason?: string;
  description?: string;
};

const COURIERS = "jne,jnt,gojek,grab";

function numberOrNull(value: unknown) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

export async function POST(request: Request) {
  const body = await request.json();
  const apiKey = process.env.BITESHIP_API_KEY;
  const originPostal = process.env.SHOP_ORIGIN_POSTAL_CODE;
  const originLatitude = numberOrNull(process.env.SHOP_ORIGIN_LATITUDE);
  const originLongitude = numberOrNull(process.env.SHOP_ORIGIN_LONGITUDE);

  if (!apiKey) {
    if (process.env.NODE_ENV === "production") {
      console.error("[shipping] BITESHIP_API_KEY missing in production — refusing to return dummy rates");
      return NextResponse.json(
        { message: "Layanan pengiriman belum tersedia. Silakan hubungi admin." },
        { status: 503 }
      );
    }
    return NextResponse.json({
      rates: dummyRates(),
      message: "BITESHIP_API_KEY belum diisi — pakai data dummy (dev only).",
    });
  }
  if (!originPostal) {
    return NextResponse.json(
      { message: "SHOP_ORIGIN_POSTAL_CODE belum di-set di .env" },
      { status: 500 }
    );
  }

  const items: ShippingItem[] = Array.isArray(body.items) ? body.items : [];
  if (items.length === 0) {
    return NextResponse.json(
      { message: "Items kosong — tidak bisa hitung ongkir." },
      { status: 400 }
    );
  }

  const destinationPostal = String(body.destinationPostalCode ?? "").trim();
  const destinationLatitude = numberOrNull(body.destinationLatitude);
  const destinationLongitude = numberOrNull(body.destinationLongitude);
  const hasOriginCoordinate = originLatitude !== null && originLongitude !== null;
  const hasDestinationCoordinate = destinationLatitude !== null && destinationLongitude !== null;

  if (!destinationPostal && !hasDestinationCoordinate) {
    return NextResponse.json(
      { message: "Kode pos atau titik koordinat tujuan harus diisi." },
      { status: 400 }
    );
  }

  // Format items sesuai spec Biteship: per item, bukan single bundle
  const biteshipItems = items.map((item) => ({
    name: item.name.slice(0, 100),
    description: item.name.slice(0, 100),
    value: Math.max(0, item.price),
    weight: Math.max(1, item.weightGram),
    quantity: Math.max(1, item.quantity),
  }));

  try {
    const res = await fetch("https://api.biteship.com/v1/rates/couriers", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: apiKey,
      },
      body: JSON.stringify({
        ...(hasOriginCoordinate
          ? { origin_latitude: originLatitude, origin_longitude: originLongitude }
          : { origin_postal_code: Number(originPostal) }),
        ...(hasDestinationCoordinate
          ? { destination_latitude: destinationLatitude, destination_longitude: destinationLongitude }
          : { destination_postal_code: Number(destinationPostal) }),
        couriers: COURIERS,
        items: biteshipItems,
      }),
    });

    if (!res.ok) {
      const text = await res.text();
      return NextResponse.json(
        { message: `Biteship error: ${text}`, rates: [] },
        { status: 500 }
      );
    }

    const data = await res.json();
    const pricing: RawPricing[] = Array.isArray(data.pricing) ? data.pricing : [];

    // Map → RateOption. Field has_cod/is_cod TIDAK ikut (abaikan).
    const rates: RateOption[] = pricing.map((p) => {
      const price = typeof p.price === "number" ? p.price : 0;
      return {
        courier_name: p.courier_name ?? p.courier_code ?? "Unknown",
        courier_code: p.courier_code,
        courier_service_name: p.courier_service_name ?? p.courier_service_code,
        courier_service_code: p.type ?? p.courier_service_code,
        service_type: normalizeServiceType(p.service_type, p.duration, p.type ?? p.courier_service_code),
        price,
        duration: formatDuration(p.duration, p.shipment_duration_range, p.shipment_duration_unit),
        available: price > 0,
        unavailable_reason:
          price > 0 ? undefined : "Tidak tersedia untuk rute / berat ini.",
        description: p.description,
      };
    }).filter((rate) => {
      if (["gojek", "grab"].includes(rate.courier_code.toLowerCase())) {
        return hasOriginCoordinate && hasDestinationCoordinate;
      }
      return true;
    });

    return NextResponse.json({ rates });
  } catch (e) {
    console.error("[shipping] error:", e);
    return NextResponse.json(
      { message: "Gagal kontak Biteship. Coba lagi.", rates: [] },
      { status: 500 }
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────

type RawPricing = {
  courier_name?: string;
  courier_code: string;
  courier_service_name?: string;
  courier_service_code: string;
  service_type?: string;
  price?: number;
  duration?: string;
  shipment_duration_range?: string;
  shipment_duration_unit?: string;
  description?: string;
  type?: string;
};

function normalizeServiceType(raw?: string, duration?: string, courierType?: string): string {
  const t = `${raw ?? ""} ${courierType ?? ""}`.toLowerCase();
  if (t.trim() === "instant") return "instant";
  if (t.trim() === "same_day") return "same_day";
  if (t.trim() === "next_day") return "next_day";
  if (t.trim() === "regular") return "regular";
  if (t.trim() === "economy") return "economy";
  if (t.includes("instant")) return "instant";
  if (t.includes("same_day") || t.includes("sameday")) return "same_day";

  const d = (duration ?? "").toLowerCase();
  if (d.includes("hour") || d.includes("jam")) return "instant";
  if (d.includes("same day") || d.includes("hari ini")) return "same_day";
  if (d.includes("next day") || d.includes("besok")) return "next_day";
  const m = d.match(/(\d+)\s*-\s*(\d+)\s*day/);
  if (m && Number(m[2]) >= 5) return "economy";
  return "regular";
}

function formatDuration(duration?: string, range?: string, unit?: string): string {
  if (duration) return duration;
  if (range) return `${range} ${unit ?? "hari"}`;
  return "—";
}

function dummyRates(): RateOption[] {
  return [
    {
      courier_name: "Gojek",
      courier_code: "gojek",
      courier_service_name: "Instant",
      courier_service_code: "instant",
      service_type: "instant",
      price: 35000,
      duration: "1-2 jam",
      available: true,
    },
    {
      courier_name: "Grab",
      courier_code: "grab",
      courier_service_name: "Same Day",
      courier_service_code: "same_day",
      service_type: "same_day",
      price: 28000,
      duration: "Hari ini",
      available: true,
    },
    {
      courier_name: "JNE",
      courier_code: "jne",
      courier_service_name: "Reguler",
      courier_service_code: "reg",
      service_type: "regular",
      price: 18000,
      duration: "2-3 hari",
      available: true,
    },
    {
      courier_name: "J&T Express",
      courier_code: "jnt",
      courier_service_name: "Reguler",
      courier_service_code: "ez",
      service_type: "regular",
      price: 17000,
      duration: "2-3 hari",
      available: true,
    },
  ];
}
