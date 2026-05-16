import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { MY_FEED_VISIBLE_STATUSES } from "@/lib/feed/my-posts";
import { deleteFeedAssets } from "@/lib/feed/cleanup";

const MAX_TITLE_LENGTH = 200;
const MAX_DESC_LENGTH = 2000;

/**
 * PATCH /api/feed/posts/[id]
 *
 * Update metadata post (title/caption, description, tagged products,
 * petType). VIDEO file TIDAK bisa di-edit — user harus delete + re-upload
 * kalau mau ganti video.
 *
 * Permissions:
 *   - Customer: edit OWN COMMUNITY post yang belum di-soft-delete. Edit
 *     reset status ke PENDING_REVIEW supaya admin re-moderate (cegah
 *     bypass: user post bagus → approved → edit jadi spam).
 *   - Admin: edit OWN admin post (any kind/tab). Status tetap ACTIVE
 *     (no re-moderation untuk admin).
 *
 * Body (semua opsional, hanya field yang di-set akan di-update):
 *   {
 *     title?: string,
 *     description?: string | null,
 *     petType?: string | null,
 *     productIds?: string[],
 *   }
 */
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  // Try ADMIN session first, fallback CUSTOMER. Same pattern as upload-url
  // (lihat lib/auth.ts cookie priority bug).
  const session =
    (await getSession("ADMIN")) ?? (await getSession("CUSTOMER"));
  if (!session) {
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const isAdmin = session.role === "ADMIN";

  // Cari post — customer hanya boleh edit OWN COMMUNITY post yang visible
  // di "My Posts". Admin boleh edit OWN post regardless of kind.
  const post = await prisma.feedPost.findFirst({
    where: {
      id: postId,
      authorId: session.sub,
      deletedAt: null,
      ...(isAdmin
        ? { authorRole: "ADMIN" }
        : {
            authorRole: "CUSTOMER",
            kind: "COMMUNITY",
            status: { in: [...MY_FEED_VISIBLE_STATUSES] },
          }),
    },
    select: {
      id: true,
      status: true,
      title: true,
      description: true,
      productId: true,
      kind: true,
    },
  });

  if (!post) {
    return NextResponse.json({ error: "Post tidak ditemukan" }, { status: 404 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    title?: string;
    description?: string | null;
    petType?: string | null;
    productIds?: unknown;
  };

  // Validate fields
  const updates: {
    title?: string;
    description?: string | null;
    productId?: string | null;
    status?: typeof post.status;
  } = {};

  if (typeof body.title === "string") {
    const t = body.title.trim();
    if (t.length === 0) {
      // Empty title not allowed (DB NOT NULL). Use placeholder.
      updates.title = "Postingan baru";
    } else if (t.length > MAX_TITLE_LENGTH) {
      return NextResponse.json(
        { error: `Judul max ${MAX_TITLE_LENGTH} karakter.` },
        { status: 400 },
      );
    } else {
      updates.title = t;
    }
  }

  // Caption / description handling — untuk customer, compose dengan petInfo
  // sama seperti di upload-url. Untuk admin, description plain.
  let composedDescription: string | null | undefined = undefined;
  if (typeof body.description !== "undefined") {
    const desc =
      body.description === null ? null : String(body.description).trim();
    if (desc !== null && desc.length > MAX_DESC_LENGTH) {
      return NextResponse.json(
        { error: `Deskripsi max ${MAX_DESC_LENGTH} karakter.` },
        { status: 400 },
      );
    }
    composedDescription = desc;
  }
  // Customer: ada petType → re-compose description dengan "Info peliharaan"
  if (!isAdmin && typeof body.petType !== "undefined") {
    const petType =
      body.petType === null ? "" : String(body.petType).trim();
    const baseDesc =
      composedDescription !== undefined ? composedDescription ?? "" : "";
    const petInfo = petType ? `Info peliharaan: ${petType}` : "";
    const finalDesc =
      [baseDesc, petInfo].filter(Boolean).join("\n\n") || null;
    updates.description = finalDesc;
  } else if (composedDescription !== undefined) {
    updates.description = composedDescription;
  }

  // Tagged products. Customer limit 3, admin 5.
  const maxTaggedProducts = isAdmin ? 5 : 3;
  let newProductIds: string[] | null = null;
  if (Array.isArray(body.productIds)) {
    const ids = body.productIds
      .map((v) => String(v ?? "").trim())
      .filter(Boolean);
    const unique = [...new Set(ids)];
    if (unique.length > maxTaggedProducts) {
      return NextResponse.json(
        { error: `Maksimal ${maxTaggedProducts} produk yang bisa di-tag.` },
        { status: 400 },
      );
    }
    newProductIds = unique;
    // Update FeedPost.productId ke primary (productIds[0]) supaya legacy
    // single-product display + product page query tetap work.
    updates.productId = unique[0] ?? null;
  }

  // Customer edit re-trigger moderation — status ke PENDING_REVIEW.
  // Admin edit stays at current status.
  if (!isAdmin && post.status === "ACTIVE") {
    updates.status = "PENDING_REVIEW";
  }

  // Apply update + replace taggedProducts (Shop the Look) di transaction.
  await prisma.$transaction(async (tx) => {
    await tx.feedPost.update({
      where: { id: post.id },
      data: {
        ...updates,
        moderatedById: session.sub,
        moderatedAt: new Date(),
      },
    });

    if (newProductIds !== null) {
      // Replace all FeedPostProduct rows (simpler than diff). FK cascade
      // pasti aman karena hanya delete via this table, FeedPost stays.
      await tx.feedPostProduct.deleteMany({ where: { feedPostId: post.id } });
      if (newProductIds.length > 0) {
        await tx.feedPostProduct.createMany({
          data: newProductIds.map((productId, position) => ({
            feedPostId: post.id,
            productId,
            position,
          })),
          skipDuplicates: true,
        });
      }
    }

    await tx.feedModerationLog.create({
      data: {
        postId: post.id,
        actorId: session.sub,
        action: isAdmin ? "admin_edit" : "user_edit",
        fromStatus: post.status,
        toStatus: updates.status ?? post.status,
        note: null,
      },
    });
  });

  return NextResponse.json({ ok: true });
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  // Select juga videoUrl / thumbnailUrl / videoGuid supaya bisa cleanup
  // Bunny + UploadThing asset setelah soft-delete commit. Sebelumnya cuma
  // ambil id+status — bug: user delete post tapi video di Bunny tetap
  // accumulate storage selamanya.
  const post = await prisma.feedPost.findFirst({
    where: {
      id: postId,
      authorId: session.sub,
      authorRole: "CUSTOMER",
      kind: "COMMUNITY",
      deletedAt: null,
      status: { in: [...MY_FEED_VISIBLE_STATUSES] },
    },
    select: {
      id: true,
      status: true,
      videoUrl: true,
      thumbnailUrl: true,
      videoGuid: true,
    },
  });

  if (!post) {
    return NextResponse.json({ error: "Post tidak ditemukan" }, { status: 404 });
  }

  const now = new Date();
  await prisma.$transaction([
    prisma.feedPost.update({
      where: { id: post.id },
      data: {
        deletedAt: now,
        moderatedById: session.sub,
        moderatedAt: now,
      },
    }),
    prisma.feedModerationLog.create({
      data: {
        postId: post.id,
        actorId: session.sub,
        action: "user_delete",
        fromStatus: post.status,
        toStatus: post.status,
        note: "Deleted by post owner",
      },
    }),
  ]);

  // Cleanup Bunny Stream video record (HLS + MP4 variants + thumbnail
  // auto-generated) + UploadThing legacy asset. Fire-and-forget — kalau
  // Bunny unreachable, soft-delete tetap commit; weekly storage GC cron
  // (/api/cron/feed-storage-gc) catch orphan nanti.
  void deleteFeedAssets({
    videoUrl: post.videoUrl,
    thumbnailUrl: post.thumbnailUrl,
    videoGuid: post.videoGuid,
    context: `user-delete ${postId}`,
  });

  return NextResponse.json({ ok: true });
}
