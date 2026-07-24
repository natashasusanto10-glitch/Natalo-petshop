import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { validateCarePayload, computeUpcoming } from "@/lib/pet-care-api";

async function getOwnedPet(id: string, userId: string) {
  return prisma.pet.findFirst({ where: { id, userId } });
}

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const pet = await getOwnedPet(id, session.sub);
  if (!pet) {
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const records = await prisma.petCareRecord.findMany({
    where: { petId: id },
    orderBy: { doneAt: "desc" },
  });

  const upcoming = computeUpcoming(
    records.map((r) => ({
      id: r.id,
      category: r.category,
      doneAt: r.doneAt,
      nextDueAt: r.nextDueAt,
    })),
  );

  return NextResponse.json({ records, upcoming });
}

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const pet = await getOwnedPet(id, session.sub);
  if (!pet) {
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const body = await request.json().catch(() => null);
  const validated = validateCarePayload(body);
  if ("error" in validated) {
    return NextResponse.json({ error: validated.error }, { status: 400 });
  }

  const record = await prisma.petCareRecord.create({
    data: { ...validated.data, petId: id },
  });

  return NextResponse.json({ record }, { status: 201 });
}
