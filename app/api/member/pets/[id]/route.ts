import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { validatePetPayload } from "@/lib/pets-api";

async function getOwnedPet(id: string, userId: string) {
  return prisma.pet.findFirst({ where: { id, userId } });
}

// PATCH — update pet { name, type, breed?, birthDate? }
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await getOwnedPet(id, session.sub);
  if (!existing) {
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const body = await request.json().catch(() => null);
  const validated = validatePetPayload(body);
  if ("error" in validated) {
    return NextResponse.json({ error: validated.error }, { status: 400 });
  }

  const pet = await prisma.pet.update({
    where: { id },
    data: validated.data,
  });

  return NextResponse.json({ pet });
}

// DELETE — hapus pet.
export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await getOwnedPet(id, session.sub);
  if (!existing) {
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  await prisma.pet.delete({ where: { id } });

  return NextResponse.json({ ok: true });
}
