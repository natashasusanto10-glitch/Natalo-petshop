import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET() {
  const session = await getSession("CUSTOMER");

  if (!session) {
    return NextResponse.json({});
  }

  // Parallel fetch user + total loyalty points dari CustomerPoint ledger.
  // points = SUM(CustomerPoint.points) per userId. Clamp ke 0 kalau hasil
  // negative (defensive — kalau ada bug claim duplicate, user tidak shock
  // lihat angka minus). Index `userId` di CustomerPoint bikin aggregate
  // ini O(log n) → reasonable performance bahkan untuk user >1000 tx.
  const [user, pointsAgg] = await Promise.all([
    prisma.user.findUnique({
      where: { id: session.sub },
      select: {
        id: true,
        role: true,
        name: true,
        username: true,
        email: true,
        phone: true,
        birthDate: true,
        createdAt: true,
        profilePhotoUrl: true,
        bio: true,
      },
    }),
    prisma.customerPoint.aggregate({
      where: { userId: session.sub },
      _sum: { points: true },
    }),
  ]);

  if (!user) return NextResponse.json({});

  const points = Math.max(0, pointsAgg._sum.points ?? 0);
  return NextResponse.json({ ...user, points });
}

/**
 * PATCH /api/auth/me — partial update profile member.
 *
 * Body opsional: `{ name?, email?, phone?, birthDate?, profilePhotoUrl? }`.
 * Hanya field yang dikirim yang di-update.
 *
 * Validation:
 * - name min 2 char
 * - email format valid (kalau dikirim)
 * - phone normalize ke format Indonesia 08xxx
 * - profilePhotoUrl harus URL (untuk hapus, kirim explicit null)
 */
export async function PATCH(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "Login member dulu." },
      { status: 401 },
    );
  }

  const body = await request.json().catch(() => ({}));
  const updates: Record<string, unknown> = {};

  if (typeof body.name === "string") {
    const name = body.name.trim();
    if (name.length < 2) {
      return NextResponse.json(
        { error: "Nama minimal 2 karakter." },
        { status: 400 },
      );
    }
    updates.name = name;
  }
  // Email + phone DI-LOCK setelah registrasi — silent ignore field
  // ini di payload (anti voucher 1×/user abuse). User schema @unique
  // di kolom email+phone, kalau dibiarkan diganti user bisa "lepas"
  // identifier lama → daftar ulang akun baru dengan identifier itu →
  // claim voucher BDAY/welcome/loyalty 1× lagi. Belt-and-suspenders
  // di server bahkan kalau client lama / external tool kirim field
  // ini. Legitimate change harus via admin (manual update di DB).
  if (body.email !== undefined || body.phone !== undefined) {
    console.warn(
      "[auth/me PATCH] email/phone field ignored — locked after registration",
      { userId: session.sub },
    );
  }
  if (body.birthDate !== undefined) {
    if (body.birthDate === null || body.birthDate === "") {
      updates.birthDate = null;
    } else {
      const parsed = new Date(body.birthDate);
      if (Number.isNaN(parsed.getTime())) {
        return NextResponse.json(
          { error: "Format tanggal lahir tidak valid." },
          { status: 400 },
        );
      }
      updates.birthDate = parsed;
    }
  }
  if (body.profilePhotoUrl !== undefined) {
    // null = explicit hapus foto. Empty string juga treated as null.
    const photoUrl =
      typeof body.profilePhotoUrl === "string" && body.profilePhotoUrl.trim().length > 0
        ? body.profilePhotoUrl.trim()
        : null;
    updates.profilePhotoUrl = photoUrl;
  }
  if (body.bio !== undefined) {
    // Bio max 150 char enforced di app — IG convention. Trim whitespace.
    // Empty string atau null = clear bio.
    if (body.bio === null) {
      updates.bio = null;
    } else if (typeof body.bio === "string") {
      const bio = body.bio.trim();
      if (bio.length > 150) {
        return NextResponse.json(
          { error: "Bio maksimal 150 karakter." },
          { status: 400 },
        );
      }
      updates.bio = bio.length > 0 ? bio : null;
    }
  }

  if (Object.keys(updates).length === 0) {
    return NextResponse.json(
      { error: "Tidak ada field yang di-update." },
      { status: 400 },
    );
  }

  try {
    const [user, pointsAgg] = await Promise.all([
      prisma.user.update({
        where: { id: session.sub },
        data: updates,
        select: {
          id: true,
          role: true,
          name: true,
          username: true,
          email: true,
          phone: true,
          birthDate: true,
          createdAt: true,
          profilePhotoUrl: true,
          bio: true,
        },
      }),
      // Same aggregate seperti GET — supaya Flutter yang replace profile
      // object full setelah PATCH tidak nge-reset points ke 0.
      prisma.customerPoint.aggregate({
        where: { userId: session.sub },
        _sum: { points: true },
      }),
    ]);
    const points = Math.max(0, pointsAgg._sum.points ?? 0);
    return NextResponse.json({ ok: true, user: { ...user, points } });
  } catch (error) {
    console.error("[auth/me PATCH] error:", error);
    return NextResponse.json(
      { error: "Update profil gagal. Coba lagi sebentar." },
      { status: 500 },
    );
  }
}
