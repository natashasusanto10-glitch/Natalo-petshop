import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const body = await request.json();
  const apiKey = process.env.BITESHIP_API_KEY;

  // Fallback agar UI bisa dites tanpa API key.
  if (!apiKey) {
    return NextResponse.json({
      rates: [
        { courier_name: "JNE", courier_code: "jne", courier_service_name: "REG", courier_service_code: "reg", price: 18000, duration: "2-3 hari" },
        { courier_name: "SiCepat", courier_code: "sicepat", courier_service_name: "Regular", courier_service_code: "reg", price: 16000, duration: "2-3 hari" },
      ],
      message: "BITESHIP_API_KEY belum diisi. Menggunakan ongkir dummy.",
    });
  }

  const totalWeight = Array.isArray(body.items)
    ? body.items.reduce((sum: number, item: { weightGram?: number; quantity?: number }) => sum + (item.weightGram || 500) * (item.quantity || 1), 0)
    : 500;

  const res = await fetch("https://api.biteship.com/v1/rates/couriers", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: apiKey,
    },
    body: JSON.stringify({
      origin_postal_code: process.env.SHOP_ORIGIN_POSTAL_CODE,
      destination_postal_code: body.destinationPostalCode,
      couriers: "jne,jnt,sicepat,anteraja,ninja",
      items: [
        {
          name: "Order website",
          description: "Produk toko",
          value: 100000,
          length: 10,
          width: 10,
          height: 10,
          weight: totalWeight,
          quantity: 1,
        },
      ],
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    return NextResponse.json({ message: `Biteship error: ${text}` }, { status: 500 });
  }

  const data = await res.json();
  return NextResponse.json({ rates: data.pricing || [] });
}
