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
      select: {
        id: true,
        name: true,
        email: true,
        phone: true,
        birthDate: true,
        // Lock timestamp — kalau != null, Flutter UI render tgl lahir
        // read-only dengan hint hubungi admin untuk ubah. Lihat
        // anti-abuse note di prisma/schema.prisma User.birthDateLockedAt.
        birthDateLockedAt: true,
        createdAt: true,
      },
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

  // Fetch current user state untuk validate phone uniqueness + birthDate
  // lock check sebelum update. Single query supaya ngirit round-trip.
  const current = await prisma.user.findUnique({
    where: { id: session.sub },
    select: {
      phone: true,
      birthDate: true,
      birthDateLockedAt: true,
    },
  });
  if (!current) {
    return NextResponse.json({ error: "User tidak ditemukan." }, { status: 404 });
  }

  // ── Anti-abuse: Shopee-strict lock birthDate ──────────────────────
  // Aturan:
  //   - Kalau birthDateLockedAt != null → birthDate TIDAK BOLEH diubah.
  //     User yang mau ralat harus hubungi admin (lihat
  //     /admin/birth-date-overrides — admin override auto-clear lock).
  //   - Kalau birthDateLockedAt == null → user bebas set/edit birthDate.
  //     Setelah save dengan birthDate non-null, auto-lock IMMEDIATE.
  //   - Special case: admin baru saja override (birthDateLockedAt = NULL
  //     tapi birthDate sudah ada) → user dapat 1× kesempatan edit lagi
  //     untuk ralat sendiri, lalu re-lock.
  //
  // Cek perubahan dengan compare ISO date string (tanpa time component)
  // supaya tidak false-positive karena timezone parsing.
  const currentDateIso = current.birthDate?.toISOString().slice(0, 10) ?? null;
  const newDateIso = birthDate?.toISOString().slice(0, 10) ?? null;
  const birthDateChanged = currentDateIso !== newDateIso;
  if (birthDateChanged && current.birthDateLockedAt) {
    return NextResponse.json(
      {
        error:
          "Tanggal lahir sudah terkunci. Untuk ubah, hubungi admin via WhatsApp dengan verifikasi identitas (sebutkan nama, email, dan no HP terdaftar).",
      },
      { status: 403 },
    );
  }

  // Check phone uniqueness (if changed)
  if (phone && phone !== current.phone) {
    const existing = await prisma.user.findFirst({
      where: { phone, NOT: { id: session.sub } },
    });
    if (existing) {
      return NextResponse.json({ error: "No. HP sudah digunakan akun lain." }, { status: 400 });
    }
  }

  // Auto-lock saat birthDate berubah ke non-null value (Opsi B Shopee
  // strict). Logic:
  //   - Saat first-time set (NULL → tgl) → lock
  //   - Saat re-set setelah admin override (lock cleared, birthDate
  //     masih ada) → user bebas edit sekali ini, lalu lock lagi
  //   - Kalau user clear birthDate (tgl → NULL) → JANGAN set lock
  //     (semantik field = "tanggal pernah dikunci"; clearing field
  //     tidak harus lock NULL)
  const shouldLock = birthDateChanged && birthDate !== null;

  const user = await prisma.user.update({
    where: { id: session.sub },
    data: {
      name,
      phone,
      birthDate,
      ...(shouldLock ? { birthDateLockedAt: new Date() } : {}),
    },
    select: {
      id: true,
      name: true,
      email: true,
      phone: true,
      birthDate: true,
      birthDateLockedAt: true,
    },
  });

  return NextResponse.json({ user });
}
