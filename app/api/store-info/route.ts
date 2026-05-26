/**
 * GET /api/store-info
 *
 * Return informasi toko fisik untuk self-pickup di Flutter:
 * - Alamat lengkap + koordinat (untuk maps)
 * - Jam operasional
 * - Kontak (WhatsApp + telepon)
 *
 * Read-only, no DB query. Pure static data dari env vars dengan
 * fallback default Natalo Petshop Medan.
 */
import { NextResponse } from "next/server";
import { DEFAULT_SHOP_ORIGIN, getOriginCoordinates } from "@/lib/shipping-origin";

export const revalidate = 3600; // 1 jam — static config

export async function GET() {
  const originCoordinates = getOriginCoordinates();
  const whatsappRaw =
    process.env.NEXT_PUBLIC_WA_NUMBER ??
    process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ??
    "6281289997113";
  const whatsapp = whatsappRaw.replace(/[^\d]/g, "");

  return NextResponse.json(
    {
      store: {
        name: process.env.NEXT_PUBLIC_BRAND_NAME ?? "Natalo Petshop",
        address: {
          line1: "JLN MT Haryono No 103 B C D",
          city: "Medan",
          province: "Sumatera Utara",
          postalCode: "20212",
          country: "Indonesia",
        },
        // Koordinat untuk maps — Natalo Petshop Medan / warehouse pickup.
        // Override via env SHOP_ORIGIN_LATITUDE/LONGITUDE atau
        // GOOGLE_STORE_LAT/LNG kalau titik toko geser.
        coordinates: {
          latitude: originCoordinates.latitude ?? DEFAULT_SHOP_ORIGIN.latitude,
          longitude: originCoordinates.longitude ?? DEFAULT_SHOP_ORIGIN.longitude,
        },
        hours: {
          weekday: { open: "09:00", close: "18:00" },
          saturday: { open: "09:00", close: "18:00" },
          sunday: null, // tutup atau sesuai info admin
          note: "Minggu / libur nasional tutup atau sesuai info admin.",
        },
        contact: {
          whatsapp,
          whatsappUrl: `https://wa.me/${whatsapp}`,
          phone: whatsappRaw,
        },
      },
    },
    {
      headers: {
        "Cache-Control": "public, s-maxage=3600, stale-while-revalidate=86400",
      },
    },
  );
}
