import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json([], { status: 200 });
  }

  const addresses = await prisma.address.findMany({
    where: { userId: session.sub },
    orderBy: [{ isMain: "desc" }, { createdAt: "asc" }],
  });

  return NextResponse.json(addresses);
}
