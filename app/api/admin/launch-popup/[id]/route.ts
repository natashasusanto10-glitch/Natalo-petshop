/**
 * /api/admin/launch-popup/[id]
 *
 * PATCH  - Update popup (gambar, alt, link, audience, jadwal, aktif).
 * DELETE - Hapus popup.
 */
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import {
  BANNER_LINK_TYPES,
  validateBannerLink,
  type BannerLinkType,
} from "@/lib/home-banners";

const updateSchema = z.object({
  imageUrl: z.string().trim().url().max(2048).optional(),
  imageAlt: z.string().trim().max(300).optional(),
  linkType: z
    .enum(BANNER_LINK_TYPES as [BannerLinkType, ...BannerLinkType[]])
    .optional(),
  linkValue: z.string().trim().max(2048).optional().nullable(),
  audience: z.enum(["all", "member"]).optional(),
  startsAt: z.string().datetime().optional().nullable(),
  endsAt: z.string().datetime().optional().nullable(),
  isActive: z.boolean().optional(),
});

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Body tidak valid" }, { status: 400 });
  }

  const parsed = updateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? "Data tidak valid" },
      { status: 400 },
    );
  }

  const existing = await prisma.launchPopup.findUnique({ where: { id } });
  if (!existing) {
    return NextResponse.json({ error: "Popup tidak ditemukan" }, { status: 404 });
  }

  // Validasi link kalau linkType/linkValue diubah — pakai nilai final
  // (gabungan existing + patch), pola sama dengan admin banners.
  const finalLinkType = parsed.data.linkType ?? existing.linkType;
  const finalLinkValue =
    parsed.data.linkValue !== undefined
      ? parsed.data.linkValue
      : existing.linkValue;
  if (parsed.data.linkType !== undefined || parsed.data.linkValue !== undefined) {
    const linkCheck = validateBannerLink(finalLinkType, finalLinkValue);
    if (!linkCheck.ok) {
      return NextResponse.json({ error: linkCheck.error }, { status: 400 });
    }
  }

  // Validasi jadwal dengan nilai final (gabungan existing + patch).
  const finalStartsAt =
    parsed.data.startsAt !== undefined
      ? parsed.data.startsAt
        ? new Date(parsed.data.startsAt)
        : null
      : existing.startsAt;
  const finalEndsAt =
    parsed.data.endsAt !== undefined
      ? parsed.data.endsAt
        ? new Date(parsed.data.endsAt)
        : null
      : existing.endsAt;
  if (finalStartsAt && finalEndsAt && finalEndsAt <= finalStartsAt) {
    return NextResponse.json(
      { error: "Tanggal berakhir harus setelah tanggal mulai" },
      { status: 400 },
    );
  }

  const popup = await prisma.launchPopup.update({
    where: { id },
    data: {
      ...(parsed.data.imageUrl !== undefined && { imageUrl: parsed.data.imageUrl }),
      ...(parsed.data.imageAlt !== undefined && { imageAlt: parsed.data.imageAlt }),
      ...(parsed.data.linkType !== undefined && { linkType: parsed.data.linkType }),
      ...(parsed.data.linkValue !== undefined && {
        linkValue:
          parsed.data.linkValue && parsed.data.linkValue.length > 0
            ? parsed.data.linkValue
            : null,
      }),
      ...(parsed.data.audience !== undefined && { audience: parsed.data.audience }),
      ...(parsed.data.startsAt !== undefined && { startsAt: finalStartsAt }),
      ...(parsed.data.endsAt !== undefined && { endsAt: finalEndsAt }),
      ...(parsed.data.isActive !== undefined && { isActive: parsed.data.isActive }),
    },
  });

  return NextResponse.json({ popup });
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  try {
    await prisma.launchPopup.delete({ where: { id } });
  } catch {
    return NextResponse.json({ error: "Popup tidak ditemukan" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
