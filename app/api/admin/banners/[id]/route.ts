/**
 * /api/admin/banners/[id]
 *
 * PATCH  - Update banner (gambar, alt, link, aktif/nonaktif).
 * DELETE - Hapus banner.
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

  const existing = await prisma.homeBanner.findUnique({ where: { id } });
  if (!existing) {
    return NextResponse.json({ error: "Banner tidak ditemukan" }, { status: 404 });
  }

  // Validasi link kalau linkType/linkValue diubah — pakai nilai final
  // (gabungan existing + patch).
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

  const banner = await prisma.homeBanner.update({
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
      ...(parsed.data.isActive !== undefined && { isActive: parsed.data.isActive }),
    },
  });

  return NextResponse.json({ banner });
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
    await prisma.homeBanner.delete({ where: { id } });
  } catch {
    return NextResponse.json({ error: "Banner tidak ditemukan" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
