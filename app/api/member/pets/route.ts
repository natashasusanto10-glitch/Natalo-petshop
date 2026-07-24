import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { validatePetPayload } from "@/lib/pets-api";
import { computeUpcoming } from "@/lib/pet-care-api";

// GET — daftar pet milik user (own profile, "Anabulku").
export async function GET() {
  const session = await getSession("CUSTOMER");
  // Admin (privilege elevation) bisa pakai flow member biasa termasuk pet.
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const pets = await prisma.pet.findMany({
    where: { userId: session.sub },
    orderBy: { createdAt: "asc" },
    include: {
      careRecords: {
        select: { id: true, category: true, doneAt: true, nextDueAt: true },
      },
    },
  });

  const shaped = pets.map((pet) => {
    const upcoming = computeUpcoming(pet.careRecords);
    const nearest = upcoming[0] ?? null;
    const { careRecords, ...rest } = pet;
    return {
      ...rest,
      careCount: careRecords.length,
      nearestDue: nearest
        ? { category: nearest.category, nextDueAt: nearest.nextDueAt }
        : null,
    };
  });

  return NextResponse.json({ pets: shaped });
}

// POST — tambah pet baru { name, type, breed?, birthDate? }
export async function POST(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  const validated = validatePetPayload(body);
  if ("error" in validated) {
    return NextResponse.json({ error: validated.error }, { status: 400 });
  }

  const pet = await prisma.pet.create({
    data: { ...validated.data, userId: session.sub },
  });

  return NextResponse.json({ pet }, { status: 201 });
}
