/**
 * POST /api/notifications/[id]/read
 *
 * Mark satu announcement sebagai dibaca oleh user yang sedang login.
 * Idempotent: upsert ke AnnouncementRead (composite PK userId+announcementId),
 * jadi multiple klik tidak duplicate.
 *
 * Anonymous user (belum login) di-401 — tidak ada track read untuk anonymous.
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function POST(
  _req: Request,
  ctx: { params: Promise<{ id: string }> }
) {
  try {
    const session = await getSession("CUSTOMER");
    if (!session?.sub) {
      return NextResponse.json({ error: "Login dulu" }, { status: 401 });
    }

    const { id } = await ctx.params;
    if (!id) {
      return NextResponse.json({ error: "id required" }, { status: 400 });
    }

    // createMany + skipDuplicates lebih aman untuk composite primary key
    // AnnouncementRead di Prisma. Jika row sudah ada, request tetap sukses.
    await prisma.announcementRead.createMany({
      data: [
        {
          userId: session.sub,
          announcementId: id,
        },
      ],
      skipDuplicates: true,
    });

    return NextResponse.json({ ok: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal error";
    console.error("[notifications/read] crashed:", err);
    return NextResponse.json(
      { ok: false, error: `Gagal mark read: ${message}` },
      { status: 500 }
    );
  }
}
