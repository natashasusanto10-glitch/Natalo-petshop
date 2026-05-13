import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import {
  addressDataFromPayload,
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

  return NextResponse.json({ addresses });
}

export async function POST(request) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const payload = normalizeAddressPayload(await request.json());
  const validationError = validateAddressPayload(payload);
  if (validationError) {
    return NextResponse.json({ error: validationError }, { status: 400 });
  }

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
