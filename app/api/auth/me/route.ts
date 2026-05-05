import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET() {
  const session = await getSession();

  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({});
  }

  const user = await prisma.user.findUnique({
    where: { id: session.sub },
    select: { name: true, email: true, phone: true },
  });

  return NextResponse.json(user ?? {});
}
