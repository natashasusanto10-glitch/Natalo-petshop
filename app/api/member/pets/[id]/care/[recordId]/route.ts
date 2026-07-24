import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string; recordId: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id, recordId } = await params;

  const pet = await prisma.pet.findFirst({
    where: { id, userId: session.sub },
  });
  if (!pet) {
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const deleted = await prisma.petCareRecord.deleteMany({
    where: { id: recordId, petId: id },
  });
  if (deleted.count === 0) {
    return NextResponse.json({ error: "Catatan tidak ditemukan." }, { status: 404 });
  }

  return NextResponse.json({ ok: true });
}
