/**
 * /api/admin/banners/reorder
 *
 * PATCH - Set urutan banner. Body: { ids: string[] } urutan baru.
 *         position di-assign sesuai index di array (0, 1, 2, ...).
 */
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";

const reorderSchema = z.object({
  ids: z.array(z.string().trim().min(1)).min(1).max(50),
});

export async function PATCH(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Body tidak valid" }, { status: 400 });
  }

  const parsed = reorderSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? "Data tidak valid" },
      { status: 400 },
    );
  }

  // Update posisi atomik — semua atau tidak sama sekali.
  await prisma.$transaction(
    parsed.data.ids.map((id, index) =>
      prisma.homeBanner.update({
        where: { id },
        data: { position: index },
      }),
    ),
  );

  return NextResponse.json({ ok: true });
}
