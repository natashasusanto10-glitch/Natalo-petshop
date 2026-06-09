/**
 * /api/admin/banners
 *
 * GET  - List semua hero banner (urut position).
 * POST - Buat banner baru (imageUrl wajib; link opsional).
 *
 * Banner di-render di slider Home app customer. Gambar di-upload via
 * /api/admin/upload (UploadThing) lebih dulu, lalu URL-nya dikirim ke sini.
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

const createSchema = z.object({
  imageUrl: z.string().trim().url().max(2048),
  imageAlt: z.string().trim().max(300).default(""),
  linkType: z.enum(BANNER_LINK_TYPES as [BannerLinkType, ...BannerLinkType[]]),
  linkValue: z.string().trim().max(2048).optional().nullable(),
  isActive: z.boolean().default(true),
});

export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const banners = await prisma.homeBanner.findMany({
    orderBy: [{ position: "asc" }, { createdAt: "desc" }],
  });
  return NextResponse.json({ banners });
}

export async function POST(request: NextRequest) {
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

  const parsed = createSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? "Data tidak valid" },
      { status: 400 },
    );
  }

  const linkCheck = validateBannerLink(parsed.data.linkType, parsed.data.linkValue);
  if (!linkCheck.ok) {
    return NextResponse.json({ error: linkCheck.error }, { status: 400 });
  }

  // Posisi baru = paling akhir (max position + 1).
  const last = await prisma.homeBanner.findFirst({
    orderBy: { position: "desc" },
    select: { position: true },
  });
  const nextPosition = (last?.position ?? -1) + 1;

  const banner = await prisma.homeBanner.create({
    data: {
      imageUrl: parsed.data.imageUrl,
      imageAlt: parsed.data.imageAlt,
      linkType: parsed.data.linkType,
      linkValue:
        parsed.data.linkValue && parsed.data.linkValue.length > 0
          ? parsed.data.linkValue
          : null,
      isActive: parsed.data.isActive,
      position: nextPosition,
    },
  });

  return NextResponse.json({ banner }, { status: 201 });
}
