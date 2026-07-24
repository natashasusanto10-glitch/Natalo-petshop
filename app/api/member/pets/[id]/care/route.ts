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

  const data = validated.data;
  const record = await prisma.petCareRecord.create({
    data: {
      petId: id,
      category: data.category,
      doneAt: data.doneAt,
      note: data.note,
      nextDueAt: data.nextDueAt,
      productId: data.productId,
      brandText: data.brandText,
      dosageNote: data.dosageNote,
      weightKg: data.weightKg,
      place: data.place,
      vaccineName: data.vaccineName,
      complaint: data.complaint,
    },
  });

  if (data.weightKg !== null && (data.category === "deworm" || data.category === "flea")) {
    await prisma.$transaction([
      prisma.pet.update({ where: { id }, data: { weightKg: data.weightKg } }),
      prisma.petWeightLog.create({
        data: { petId: id, weightKg: data.weightKg, careRecordId: record.id },
      }),
    ]);
  }

  return NextResponse.json({ record }, { status: 201 });
}
