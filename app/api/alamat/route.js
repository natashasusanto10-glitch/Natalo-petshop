import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

const MAX_ADDRESSES = 3;
const PHONE_RE = /^(\+?62|0)8[1-9][0-9]{6,12}$/;

function normalizePayload(body) {
  const lat = Number(body.latitude);
  const lng = Number(body.longitude);

  // Support both "city" as string (simple) or as region object
  const cityName = typeof body.city === "object"
    ? String(body.city?.name ?? "").trim()
    : String(body.city || "").trim();

  return {
    label: String(body.label || "Rumah").trim() || "Rumah",
    recipient: String(body.recipient || body.recipientName || "").trim(),
    phone: String(body.phone || "").trim(),
    address: String(body.address || "").trim(),
    city: cityName,
    postalCode: String(body.postalCode || "").trim(),
    isMain: Boolean(body.isMain),
    latitude: Number.isFinite(lat) ? lat : null,
    longitude: Number.isFinite(lng) ? lng : null,
    pinpointAddress: String(body.pinpointAddress || "").trim() || null,
    streetName: String(body.streetName || "").trim() || null,
  };
}

function validateAddress(payload, { requirePinpoint = true } = {}) {
  if (!payload.recipient || !payload.phone || !payload.address || !payload.postalCode) {
    return "Semua field wajib diisi.";
  }

  if (!PHONE_RE.test(payload.phone.replace(/\s/g, ""))) {
    return "No. HP harus format Indonesia, contoh 08123456789 atau +628123456789.";
  }

  if (requirePinpoint && (payload.latitude === null || payload.longitude === null)) {
    return "Pinpoint titik GPS wajib diisi.";
  }

  if (payload.latitude !== null && (payload.latitude < -90 || payload.latitude > 90)) {
    return "Koordinat latitude tidak valid.";
  }
  if (payload.longitude !== null && (payload.longitude < -180 || payload.longitude > 180)) {
    return "Koordinat longitude tidak valid.";
  }

  return null;
}

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const addresses = await prisma.address.findMany({
    where: { userId: session.sub },
    orderBy: [{ isMain: "desc" }, { createdAt: "asc" }],
  });

  return NextResponse.json({ addresses });
}

export async function POST(request) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const payload = normalizePayload(await request.json());
  const validationError = validateAddress(payload, { requirePinpoint: false });
  if (validationError) {
    return NextResponse.json({ error: validationError }, { status: 400 });
  }

  const existingCount = await prisma.address.count({ where: { userId: session.sub } });
  if (existingCount >= MAX_ADDRESSES) {
    return NextResponse.json(
      { error: `Maksimal ${MAX_ADDRESSES} alamat per user.` },
      { status: 400 }
    );
  }

  const shouldBeMain = payload.isMain || existingCount === 0;
  const address = await prisma.$transaction(async (tx) => {
    if (shouldBeMain) {
      await tx.address.updateMany({ where: { userId: session.sub }, data: { isMain: false } });
    }

    return tx.address.create({
      data: {
        userId: session.sub,
        label: payload.label,
        recipient: payload.recipient,
        phone: payload.phone,
        address: payload.address,
        city: payload.city || null,
        postalCode: payload.postalCode,
        latitude: payload.latitude,
        longitude: payload.longitude,
        pinpointAddress: payload.pinpointAddress,
        streetName: payload.streetName,
        isMain: shouldBeMain,
      },
    });
  });

  return NextResponse.json({ address }, { status: 201 });
}
