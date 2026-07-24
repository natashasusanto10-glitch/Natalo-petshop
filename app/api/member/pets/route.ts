import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { validatePetPayload } from "@/lib/pets-api";

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
  });

  return NextResponse.json({ pets });
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
