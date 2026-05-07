import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

const PHONE_RE = /^(\+?62|0)8[1-9][0-9]{6,12}$/;

function normalizePayload(body) {
  const lat = Number(body.latitude);
  const lng = Number(body.longitude);

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

function validateAddress(payload) {
  if (!payload.recipient || !payload.phone || !payload.address || !payload.postalCode) {
    return "Semua field wajib diisi.";
  }

  if (!PHONE_RE.test(payload.phone.replace(/\s/g, ""))) {
    return "No. HP harus format Indonesia, contoh 08123456789 atau +628123456789.";
  }

  if (payload.latitude !== null && (payload.latitude < -90 || payload.latitude > 90)) {
    return "Koordinat latitude tidak valid.";
  }
  if (payload.longitude !== null && (payload.longitude < -180 || payload.longitude > 180)) {
    return "Koordinat longitude tidak valid.";
  }

  return null;
}

async function getOwnedAddress(id, userId) {
  return prisma.address.findFirst({ where: { id, userId } });
}

export async function PUT(request, { params }) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await getOwnedAddress(id, session.sub);
  if (!existing) return NextResponse.json({ error: "Alamat tidak ditemukan." }, { status: 404 });

  const payload = normalizePayload(await request.json());
  const validationError = validateAddress(payload);
  if (validationError) {
    return NextResponse.json({ error: validationError }, { status: 400 });
  }

  const address = await prisma.$transaction(async (tx) => {
    if (payload.isMain) {
      await tx.address.updateMany({ where: { userId: session.sub }, data: { isMain: false } });
    }

    return tx.address.update({
      where: { id },
      data: {
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
        isMain: payload.isMain || existing.isMain,
      },
    });
  });

  return NextResponse.json({ address });
}

export async function DELETE(_request, { params }) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await getOwnedAddress(id, session.sub);
  if (!existing) return NextResponse.json({ error: "Alamat tidak ditemukan." }, { status: 404 });

  await prisma.$transaction(async (tx) => {
    await tx.address.delete({ where: { id } });
    if (existing.isMain) {
      const next = await tx.address.findFirst({
        where: { userId: session.sub },
        orderBy: { createdAt: "asc" },
      });
      if (next) await tx.address.update({ where: { id: next.id }, data: { isMain: true } });
    }
  });

  return NextResponse.json({ ok: true });
}
