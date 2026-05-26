"use server";

/**
 * Server actions untuk admin override tanggal lahir customer.
 *
 * Konteks: sistem otomatis lock User.birthDate setelah customer dapat
 * voucher ultah pertama (anti-abuse — cegah ganti2 tgl lahir farm voucher).
 * Tapi ada genuine cases yang butuh override:
 *   - Customer salah input saat register
 *   - Tgl lahir berubah resmi (mis. update KTP)
 *   - Customer service request via WA
 *
 * Endpoint ini kasih CS team interface yang aman dengan audit log,
 * tanpa harus pegang Prisma Studio / SQL.
 *
 * Security:
 *   - requireAdmin guard di setiap action
 *   - reason wajib min 10 char (paksa CS dokumentasi alasan)
 *   - Audit log USER_BIRTHDATE_OVERRIDDEN dengan old/new + reason
 */

import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { AdminAction, logAdminAction } from "@/lib/admin-audit";

async function requireAdmin() {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    throw new Error("Akses ditolak. Hanya admin yang bisa eksekusi.");
  }
  return session;
}

export type UserSearchResult = {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  birthDate: string | null;
  birthDateLockedAt: string | null;
  birthdayVoucherYear: number | null;
  createdAt: string;
};

/**
 * Cari customer by email, phone, atau name (partial match).
 * Limit 20 results supaya UI tidak overflow + Postgres tidak full scan.
 * Sort by createdAt DESC supaya user terbaru di atas (helpful kalau CS
 * cari customer yang baru register-an).
 */
export async function searchUserByQuery(
  query: string,
): Promise<UserSearchResult[]> {
  await requireAdmin();
  const q = query.trim();
  if (q.length < 2) return [];

  const users = await prisma.user.findMany({
    where: {
      role: "CUSTOMER",
      OR: [
        { email: { contains: q, mode: "insensitive" } },
        { phone: { contains: q } },
        { name: { contains: q, mode: "insensitive" } },
      ],
    },
    select: {
      id: true,
      name: true,
      email: true,
      phone: true,
      birthDate: true,
      birthDateLockedAt: true,
      birthdayVoucherYear: true,
      createdAt: true,
    },
    take: 20,
    orderBy: { createdAt: "desc" },
  });

  return users.map((u) => ({
    id: u.id,
    name: u.name,
    email: u.email,
    phone: u.phone,
    birthDate: u.birthDate?.toISOString() ?? null,
    birthDateLockedAt: u.birthDateLockedAt?.toISOString() ?? null,
    birthdayVoucherYear: u.birthdayVoucherYear,
    createdAt: u.createdAt.toISOString(),
  }));
}

export type OverrideResult = {
  ok: boolean;
  message: string;
};

/**
 * Override birthDate + unlock. Reset `birthDateLockedAt` ke null supaya
 * customer bisa edit sekali lagi di Flutter (kalau dapat voucher lagi
 * nanti, otomatis lock lagi).
 *
 * Audit log:
 *   - actor = admin yang eksekusi
 *   - target = user yang di-override
 *   - summary = "Override tgl lahir {name}: {old} → {new}"
 *   - metadata = oldBirthDate, newBirthDate, previousLock, reason
 *
 * Validation:
 *   - reason min 10 char (paksa CS dokumentasi)
 *   - newBirthDate harus dalam range masuk akal (1900 < year < currentYear)
 *   - birthDate boleh null (clear field) tapi reason tetap wajib
 */
export async function unlockAndUpdateBirthDate(
  _prevState: OverrideResult,
  formData: FormData,
): Promise<OverrideResult> {
  const session = await requireAdmin();
  const userId = String(formData.get("userId") ?? "").trim();
  const newBirthDateRaw = String(formData.get("newBirthDate") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();

  if (!userId) {
    return { ok: false, message: "User ID kosong." };
  }
  if (reason.length < 10) {
    return {
      ok: false,
      message: "Alasan wajib minimum 10 karakter — diperlukan untuk audit.",
    };
  }
  if (reason.length > 500) {
    return { ok: false, message: "Alasan maksimum 500 karakter." };
  }

  let newBirthDate: Date | null = null;
  if (newBirthDateRaw.length > 0) {
    const parsed = new Date(newBirthDateRaw);
    if (isNaN(parsed.getTime())) {
      return { ok: false, message: "Format tanggal tidak valid." };
    }
    const year = parsed.getFullYear();
    const currentYear = new Date().getFullYear();
    if (year < 1900 || year > currentYear) {
      return {
        ok: false,
        message: `Tahun tgl lahir harus 1900–${currentYear}.`,
      };
    }
    newBirthDate = parsed;
  }

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      name: true,
      email: true,
      birthDate: true,
      birthDateLockedAt: true,
      role: true,
    },
  });
  if (!user) return { ok: false, message: "User tidak ditemukan." };
  if (user.role !== "CUSTOMER") {
    return { ok: false, message: "Hanya CUSTOMER yang bisa di-override." };
  }

  // Update atomic: birthDate + unlock. Setelah unlock, user bisa edit
  // tgl lahir 1× lagi di Flutter sendiri (kalau ternyata admin salah
  // input juga). Kalau user dapat voucher lagi → otomatis lock lagi.
  await prisma.user.update({
    where: { id: userId },
    data: {
      birthDate: newBirthDate,
      birthDateLockedAt: null,
    },
  });

  const oldIso = user.birthDate?.toISOString().slice(0, 10) ?? "—";
  const newIso = newBirthDate?.toISOString().slice(0, 10) ?? "—";

  logAdminAction({
    actorUserId: session.sub,
    action: AdminAction.USER_BIRTHDATE_OVERRIDDEN,
    targetType: "User",
    targetId: userId,
    summary: `Override tgl lahir ${user.name} (${user.email ?? "no email"}): ${oldIso} → ${newIso}`,
    metadata: {
      userName: user.name,
      userEmail: user.email,
      oldBirthDate: user.birthDate?.toISOString() ?? null,
      newBirthDate: newBirthDate?.toISOString() ?? null,
      previousLockedAt: user.birthDateLockedAt?.toISOString() ?? null,
      reason,
    },
  });

  revalidatePath("/admin/birth-date-overrides");

  return {
    ok: true,
    message: `Berhasil update tgl lahir ${user.name}: ${oldIso} → ${newIso}. User akan bisa edit 1× lagi sendiri di app.`,
  };
}
