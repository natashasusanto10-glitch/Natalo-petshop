/**
 * /api/admin/launch-popup
 *
 * GET  - List semua popup promo cold-start (terbaru dulu).
 * POST - Buat popup baru (imageUrl wajib; link/jadwal/audience opsional).
 *
 * Popup di-render fullscreen di app Flutter saat cold start (gaya Shopee:
 * satu gambar kreatif + tombol X). Gambar di-upload via /api/admin/upload
 * (UploadThing) lebih dulu, lalu URL-nya dikirim ke sini — pola sama
 * dengan /api/admin/banners.
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
  audience: z.enum(["all", "member"]).default("member"),
  // Datetime ISO string (datetime-local admin form → toISOString) atau null.
  startsAt: z.string().datetime().optional().nullable(),
  endsAt: z.string().datetime().optional().nullable(),
  isActive: z.boolean().default(true),
});

export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const popups = await prisma.launchPopup.findMany({
    orderBy: { createdAt: "desc" },
  });
  return NextResponse.json({ popups });
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

  const startsAt = parsed.data.startsAt ? new Date(parsed.data.startsAt) : null;
  const endsAt = parsed.data.endsAt ? new Date(parsed.data.endsAt) : null;
  if (startsAt && endsAt && endsAt <= startsAt) {
    return NextResponse.json(
      { error: "Tanggal berakhir harus setelah tanggal mulai" },
      { status: 400 },
    );
  }

  const popup = await prisma.launchPopup.create({
    data: {
      imageUrl: parsed.data.imageUrl,
      imageAlt: parsed.data.imageAlt,
      linkType: parsed.data.linkType,
      linkValue:
        parsed.data.linkValue && parsed.data.linkValue.length > 0
          ? parsed.data.linkValue
          : null,
      audience: parsed.data.audience,
      startsAt,
      endsAt,
      isActive: parsed.data.isActive,
    },
  });

  return NextResponse.json({ popup }, { status: 201 });
}
