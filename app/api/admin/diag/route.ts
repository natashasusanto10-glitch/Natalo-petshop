/**
 * GET /api/admin/diag
 *
 * Admin-only diagnostic — tunjukin DB yang sedang aktif dipakai backend.
 * Dipakai untuk verifikasi "apakah Vercel sudah point ke DB baru?".
 *
 * Return:
 *   {
 *     dbHost: "ep-xxxx-pooler.us-east-2.aws.neon.tech",  // masked
 *     userCount: 1234,
 *     productCount: 567,
 *     orderCount: 89,
 *     environment: "production" | "development",
 *     serverTime: "2026-05-21T14:30:00.000Z",
 *     latestMigration: "20260521010000_seed_consumable_categories"
 *   }
 *
 * Cara pakai (saat user khawatir DB salah):
 *   1. Login sebagai admin di app/dashboard
 *   2. Buka URL ini di browser
 *   3. Bandingkan `dbHost` dengan DB yang ingin dipakai
 *   4. Bandingkan `userCount` dengan yang user expect
 *
 * Auth: ADMIN session only (403 untuk customer / guest).
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

/** Mask password + sensitive part dari connection string. */
function maskDbUrl(url: string | undefined): string {
  if (!url) return "(not set)";
  try {
    // postgresql://user:password@host:port/db?param=...
    const parsed = new URL(url);
    return `${parsed.protocol}//${parsed.username}@${parsed.hostname}${parsed.port ? `:${parsed.port}` : ""}${parsed.pathname}`;
  } catch {
    // Kalau gagal parse, return prefix saja.
    return url.length > 30 ? `${url.slice(0, 30)}…` : url;
  }
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
    const [userCount, productCount, orderCount, recentMigrations] =
      await Promise.all([
        prisma.user.count(),
        prisma.product.count(),
        prisma.order.count(),
        prisma.$queryRaw<{ migration_name: string; finished_at: Date | null }[]>`
          SELECT "migration_name", "finished_at"
          FROM "_prisma_migrations"
          ORDER BY "finished_at" DESC NULLS LAST
          LIMIT 5
        `.catch(() => []),
      ]);

    return NextResponse.json({
      dbHost: maskDbUrl(process.env.DATABASE_URL),
      directDbHost: maskDbUrl(process.env.DIRECT_URL),
      environment: process.env.NODE_ENV ?? "unknown",
      vercelEnv: process.env.VERCEL_ENV ?? "(not on vercel)",
      serverTime: new Date().toISOString(),
      counts: {
        users: userCount,
        products: productCount,
        orders: orderCount,
      },
      latestMigrations: recentMigrations.map((m) => ({
        name: m.migration_name,
        appliedAt: m.finished_at?.toISOString() ?? null,
      })),
    });
  } catch (error) {
    return NextResponse.json(
      {
        dbHost: maskDbUrl(process.env.DATABASE_URL),
        error: "DB_QUERY_FAILED",
        message: error instanceof Error ? error.message : String(error),
      },
      { status: 500 },
    );
  }
}
