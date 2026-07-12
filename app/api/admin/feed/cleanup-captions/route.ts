/**
 * GET /api/admin/feed/cleanup-captions  (admin-only)
 *
 * Bersih-bersih RETROAKTIF: post feed admin lama yang caption-nya dibuat
 * sebelum PR "caption AI jangan ulang judul" (mis. "Si Meong", "Majes")
 * masih berisi baris heading "# <judul diulang>" + belasan hashtag.
 * Endpoint ini menjalankan sanitizeCaption() yang sama ke SEMUA post admin
 * yang punya description, dan hanya meng-update baris yang benar-benar
 * berubah (idempoten — aman dijalankan berkali-kali; caption yang sudah
 * bersih tak tersentuh).
 *
 * Buka sekali di browser (GET, mudah di-screenshot) setelah deploy.
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { sanitizeCaption } from "@/lib/ai/generate-feed-post";

export async function GET() {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const posts = await prisma.feedPost.findMany({
    where: { authorRole: "ADMIN", description: { not: null } },
    select: { id: true, title: true, description: true },
  });

  const changed: Array<{ id: string; title: string; before: string; after: string }> = [];

  for (const post of posts) {
    if (!post.description) continue;
    const cleaned = sanitizeCaption(post.description);
    if (cleaned !== post.description) {
      await prisma.feedPost.update({
        where: { id: post.id },
        data: { description: cleaned },
      });
      changed.push({
        id: post.id,
        title: post.title.slice(0, 40),
        before: post.description.slice(0, 60),
        after: cleaned.slice(0, 60),
      });
    }
  }

  return NextResponse.json({
    scanned: posts.length,
    changedCount: changed.length,
    changed,
  });
}
