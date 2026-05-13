import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import {
  addressDataFromPayload,
  biteshipAreaPatchForAddress,
  enrichAddressPayload,
  normalizeAddressPayload,
  validateAddressPayload,
} from "@/lib/address-api";
import { prisma } from "@/lib/prisma";

async function getOwnedAddress(id, userId) {
  return prisma.address.findFirst({ where: { id, userId } });
}

export async function GET(_request, { params }) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await getOwnedAddress(id, session.sub);
  if (!existing) return NextResponse.json({ error: "Alamat tidak ditemukan." }, { status: 404 });

  const patch = await biteshipAreaPatchForAddress(existing).catch(() => null);
  const address = patch
    ? await prisma.address.update({ where: { id: existing.id }, data: patch })
    : existing;

  return NextResponse.json({ address });
}

async function updateAddress(request, { params }) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await getOwnedAddress(id, session.sub);
  if (!existing) return NextResponse.json({ error: "Alamat tidak ditemukan." }, { status: 404 });

  const normalizedPayload = normalizeAddressPayload(await request.json());
  const validationError = validateAddressPayload(normalizedPayload);
  if (validationError) {
    return NextResponse.json({ error: validationError }, { status: 400 });
  }
  const payload = await enrichAddressPayload(normalizedPayload);

  const address = await prisma.$transaction(async (tx) => {
    if (payload.isMain) {
      await tx.address.updateMany({ where: { userId: session.sub }, data: { isMain: false } });
    }

    return tx.address.update({
      where: { id },
      data: {
        ...addressDataFromPayload(payload),
        isMain: payload.isMain || existing.isMain,
      },
    });
  });

  return NextResponse.json({ address });
}

export const PUT = updateAddress;
export const PATCH = updateAddress;

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
        orderBy: { createdAt: "desc" },
      });
      if (next) await tx.address.update({ where: { id: next.id }, data: { isMain: true } });
    }
  });

  return NextResponse.json({ ok: true });
}
