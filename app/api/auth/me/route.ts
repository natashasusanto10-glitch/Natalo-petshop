import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { normalizeIndonesianPhone } from "@/lib/phone";

export async function GET() {
  const session = await getSession("CUSTOMER");

  if (!session) {
    return NextResponse.json({});
  }

  const user = await prisma.user.findUnique({
    where: { id: session.sub },
    select: {
      id: true,
      role: true,
      name: true,
      email: true,
      phone: true,
      birthDate: true,
      createdAt: true,
      profilePhotoUrl: true,
      bio: true,
    },
  });

  return NextResponse.json(user ?? {});
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
  if (typeof body.email === "string") {
    const email = body.email.trim().toLowerCase();
    if (email.length > 0 && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return NextResponse.json(
        { error: "Format email tidak valid." },
        { status: 400 },
      );
    }
    updates.email = email.length > 0 ? email : null;
  }
  if (typeof body.phone === "string") {
    const phone = normalizeIndonesianPhone(body.phone);
    if (phone.length > 0 && phone.length < 8) {
      return NextResponse.json(
        { error: "Nomor handphone tidak valid." },
        { status: 400 },
      );
    }
    updates.phone = phone.length > 0 ? phone : null;
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
    const user = await prisma.user.update({
      where: { id: session.sub },
      data: updates,
      select: {
        id: true,
        role: true,
        name: true,
        email: true,
        phone: true,
        birthDate: true,
        createdAt: true,
        profilePhotoUrl: true,
        bio: true,
      },
    });
    return NextResponse.json({ ok: true, user });
  } catch (error) {
    console.error("[auth/me PATCH] error:", error);
    return NextResponse.json(
      { error: "Update profil gagal. Coba lagi sebentar." },
      { status: 500 },
    );
  }
}
