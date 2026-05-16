import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  // Fetch user + aggregated loyalty points secara paralel. Points di-include
  // di response profile supaya mobile/Flutter app cukup 1 call untuk dapat
  // semua data dashboard member (nama, kontak, saldo poin).
  const [user, pointsAgg] = await Promise.all([
    prisma.user.findUnique({
      where: { id: session.sub },
      select: { id: true, name: true, email: true, phone: true, birthDate: true, createdAt: true },
    }),
    prisma.customerPoint
      .aggregate({
        where: { userId: session.sub },
        _sum: { points: true },
      })
      .catch(() => ({ _sum: { points: 0 } })),
  ]);

  if (!user) return NextResponse.json({ error: "User tidak ditemukan." }, { status: 404 });
  const points = pointsAgg._sum.points ?? 0;
  return NextResponse.json({ user: { ...user, points } });
}

export async function PUT(request: Request) {
  const session = await getSession("CUSTOMER");
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const body = await request.json();
  const name = String(body.name || "").trim();
  const phone = String(body.phone || "").trim() || null;
  const birthDateRaw = String(body.birthDate || "").trim();

  if (!name) return NextResponse.json({ error: "Nama tidak boleh kosong." }, { status: 400 });

  const PHONE_RE = /^(\+?62|0)8[1-9][0-9]{6,12}$/;
  if (phone && !PHONE_RE.test(phone.replace(/\s/g, ""))) {
    return NextResponse.json(
      { error: "No. HP harus format Indonesia, contoh 08123456789 atau +628123456789." },
      { status: 400 }
    );
  }

  let birthDate: Date | null = null;
  if (birthDateRaw) {
    const parsed = new Date(birthDateRaw);
    if (isNaN(parsed.getTime())) {
      return NextResponse.json({ error: "Format tanggal lahir tidak valid." }, { status: 400 });
    }
    birthDate = parsed;
  }

  // Check phone uniqueness (if changed)
  if (phone) {
    const existing = await prisma.user.findFirst({
      where: { phone, NOT: { id: session.sub } },
    });
    if (existing) {
      return NextResponse.json({ error: "No. HP sudah digunakan akun lain." }, { status: 400 });
    }
  }

  const user = await prisma.user.update({
    where: { id: session.sub },
    data: { name, phone, birthDate },
    select: { id: true, name: true, email: true, phone: true, birthDate: true },
  });

  return NextResponse.json({ user });
}
