import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function PATCH(_request, { params }) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await prisma.address.findFirst({ where: { id, userId: session.sub } });
  if (!existing) return NextResponse.json({ error: "Alamat tidak ditemukan." }, { status: 404 });

  const address = await prisma.$transaction(async (tx) => {
    await tx.address.updateMany({
      where: { userId: session.sub, isMain: true },
      data: { isMain: false },
    });
    return tx.address.update({
      where: { id },
      data: { isMain: true },
    });
  });

  return NextResponse.json({ address });
}

export const POST = PATCH;
