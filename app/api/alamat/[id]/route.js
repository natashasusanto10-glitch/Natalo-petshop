import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

const PHONE_RE = /^(\+?62|0)8[1-9][0-9]{6,12}$/;

function region(input) {
  return {
    code: String(input?.code ?? "").trim(),
    name: String(input?.name ?? "").trim(),
    postalCode: String(input?.postalCode ?? "").trim(),
  };
}

function normalizePayload(body) {
  const province = region(body.province);
  const city = region(body.city);
  const district = region(body.district);
  const village = region(body.village);
  const lat = Number(body.latitude);
  const lng = Number(body.longitude);

  return {
    label: String(body.label || "Rumah").trim() || "Rumah",
    recipientName: String(body.recipientName || "").trim(),
    phone: String(body.phone || "").trim(),
    address: String(body.address || "").trim(),
    province,
    city,
    district,
    village,
    postalCode: String(body.postalCode || village.postalCode || "").trim(),
    isMain: Boolean(body.isMain),
    latitude: Number.isFinite(lat) ? lat : null,
    longitude: Number.isFinite(lng) ? lng : null,
    pinpointAddress: String(body.pinpointAddress || "").trim() || null,
    streetName: String(body.streetName || "").trim() || null,
  };
}

function validateAddress(payload) {
  if (
    !payload.recipientName ||
    !payload.phone ||
    !payload.address ||
    !payload.province.name ||
    !payload.city.name ||
    !payload.district.name ||
    !payload.village.name ||
    !payload.postalCode
  ) {
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
  const session = await getSession();
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
        recipientName: payload.recipientName,
        phone: payload.phone,
        address: payload.address,
        province: payload.province.name,
        provinceCode: payload.province.code || null,
        city: payload.city.name,
        cityCode: payload.city.code || null,
        district: payload.district.name,
        districtCode: payload.district.code || null,
        village: payload.village.name,
        villageCode: payload.village.code || null,
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
  const session = await getSession();
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
