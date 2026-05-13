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

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const addresses = await prisma.address.findMany({
    where: { userId: session.sub },
    orderBy: [{ isMain: "desc" }, { createdAt: "asc" }],
  });

  const repairedAddresses = await Promise.all(
    addresses.map(async (address) => {
      const patch = await biteshipAreaPatchForAddress(address).catch(() => null);
      if (!patch) return address;

      return prisma.address.update({
        where: { id: address.id },
        data: patch,
      });
    }),
  );

  return NextResponse.json({ addresses: repairedAddresses });
}

export async function POST(request) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const normalizedPayload = normalizeAddressPayload(await request.json());
  const validationError = validateAddressPayload(normalizedPayload);
  if (validationError) {
    return NextResponse.json({ error: validationError }, { status: 400 });
  }
  const payload = await enrichAddressPayload(normalizedPayload);

  const existingCount = await prisma.address.count({ where: { userId: session.sub } });
  const shouldBeMain = payload.isMain || existingCount === 0;
  const address = await prisma.$transaction(async (tx) => {
    if (shouldBeMain) {
      await tx.address.updateMany({ where: { userId: session.sub }, data: { isMain: false } });
    }

    return tx.address.create({
      data: {
        ...addressDataFromPayload(payload, session.sub),
        isMain: shouldBeMain,
      },
    });
  });

  return NextResponse.json({ address }, { status: 201 });
}
