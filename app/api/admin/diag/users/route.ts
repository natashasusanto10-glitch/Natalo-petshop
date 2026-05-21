/**
 * GET /api/admin/diag/users
 *
 * Admin-only — list semua user di DB sekarang dengan info untuk
 * identifikasi: kapan dibuat, apakah pernah login (lastLoginAt), email,
 * phone, role.
 *
 * Dipakai untuk verify user mana yang ada di DB — kalau user pertanyaan
 * "user lama bisa login di DB baru", buka URL ini untuk lihat siapa
 * 4 user yang ada di DB sekarang.
 *
 * Return:
 *   {
 *     count: 4,
 *     users: [
 *       {
 *         id: "cl4abc...",
 *         name: "John Doe",
 *         email: "j***@e****.com",  // masked
 *         phone: "0812****1234",     // masked
 *         role: "CUSTOMER" | "ADMIN",
 *         createdAt: "...",
 *         lastLoginAt: "..." | null,
 *         tokenVersion: 0
 *       }
 *     ]
 *   }
 *
 * Auth: ADMIN only (401 untuk customer/guest).
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

function maskEmail(email: string | null): string {
  if (!email) return "(no email)";
  const [local, domain] = email.split("@");
  if (!domain) return email;
  const masked = local.length <= 2
    ? `${local[0]}***`
    : `${local[0]}${"*".repeat(local.length - 2)}${local[local.length - 1]}`;
  return `${masked}@${domain}`;
}

function maskPhone(phone: string | null): string {
  if (!phone) return "(no phone)";
  if (phone.length <= 6) return phone;
  return `${phone.slice(0, 4)}${"*".repeat(phone.length - 8)}${phone.slice(-4)}`;
}

export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json(
      { error: "UNAUTHORIZED", message: "Admin login required" },
      { status: 401 },
    );
  }

  try {
    const users = await prisma.user.findMany({
      orderBy: { createdAt: "asc" },
      select: {
        id: true,
        name: true,
        email: true,
        phone: true,
        role: true,
        createdAt: true,
        tokenVersion: true,
      },
    });

    return NextResponse.json({
      count: users.length,
      users: users.map((u) => ({
        id: u.id,
        name: u.name,
        email: maskEmail(u.email),
        phone: maskPhone(u.phone),
        role: u.role,
        createdAt: u.createdAt.toISOString(),
        tokenVersion: u.tokenVersion,
      })),
    });
  } catch (error) {
    return NextResponse.json(
      {
        error: "DB_QUERY_FAILED",
        message: error instanceof Error ? error.message : String(error),
      },
      { status: 500 },
    );
  }
}
