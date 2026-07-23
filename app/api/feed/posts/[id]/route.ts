import { after, NextRequest, NextResponse } from "next/server";
import type { Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { MY_FEED_VISIBLE_STATUSES } from "@/lib/feed/my-posts";
import { deleteFeedAssets } from "@/lib/feed/cleanup";
import { signBunnyUrl } from "@/lib/feed/bunny";
import { buildFeedVideoPlaybackUrls } from "@/lib/feed/video-playback-urls";
import { editReTriggersModeration } from "@/lib/feed/post-moderation";
import {
  getViewerSavedPostIds,
  resolveFeedProductDiscount,
} from "@/lib/feed/queries";
import { brandDisplayName, brandPhotoUrl } from "@/lib/social/brand-user";
import { TAGGED_USERS_SELECT, serializeTaggedUsers } from "@/lib/feed/tagged-users";
import { buildFeedShareVersion } from "@/lib/share/feed-share-data";
import {
  feedAccessibilityPayload,
  parseFeedAccessibilityMetadata,
  parseFeedAltText,
} from "@/lib/feed/accessibility";

const MAX_TITLE_LENGTH = 200;
const MAX_DESC_LENGTH = 2000;

function singlePostProductSelect(now: Date) {
  return {
    id: true,
    slug: true,
    name: true,
    price: true,
    discountPrice: true,
    flashSaleEndsAt: true,
    discountItems: {
      where: {
        isItemActive: true,
        discount: {
          isActive: true,
          startsAt: { lte: now },
          endsAt: { gt: now },
        },
      },
      select: {
        variantId: true,
        discountedPrice: true,
        discount: { select: { endsAt: true } },
      },
    },
    stock: true,
    weightGram: true,
    isActive: true,
    imageUrl: true,
    hasVariants: true,
    avgRating: true,
    reviewCount: true,
  } satisfies Prisma.ProductSelect;
}

/**
 * GET /api/feed/posts/[id]
 *
 * Viewer-facing single post fetch. Dipakai saat user tap deep-link
 * notif "X posting video/foto baru" (`/feed/<postId>`) → Flutter fetch
 * post by ID lalu buka MemberPostDetailScreen.
 *
 * Hanya return post yang ACTIVE + tidak deleted (public visibility) —
 * post PENDING/REJECTED/HIDDEN return 404 (viewer tidak boleh lihat).
 * Shape mirror item `/api/u/[username]` supaya `FeedPost.fromJson` di
 * Flutter parse tanpa perubahan. Bunny URL di-sign untuk hotlink
 * protection. viewerLiked di-resolve kalau ada session.
 */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  if (!id) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const now = new Date();
  const productSelect = singlePostProductSelect(now);

  const post = await prisma.feedPost.findFirst({
    where: { id, status: "ACTIVE", deletedAt: null },
    select: {
      id: true,
      kind: true,
      title: true,
      description: true,
      thumbnailUrl: true,
      thumbnailBlurhash: true,
      videoUrl: true,
      videoGuid: true,
      videoDurationSec: true,
      videoWidth: true,
      videoHeight: true,
      videoAltText: true,
      hasAudio: true,
      subtitleUrl: true,
      subtitleLanguage: true,
      createdAt: true,
      likeCount: true,
      commentCount: true,
      viewCount: true,
      authorRole: true,
      product: { select: productSelect },
      taggedProducts: {
        orderBy: { position: "asc" },
        select: {
          position: true,
          promoPrice: true,
          product: { select: productSelect },
        },
      },
      author: {
        select: {
          id: true,
          name: true,
          username: true,
          role: true,
          profilePhotoUrl: true,
        },
      },
      media: {
        orderBy: { sortOrder: "asc" },
        select: {
          id: true,
          url: true,
          thumbnailUrl: true,
          mediaType: true,
          width: true,
          height: true,
          altText: true,
        },
      },
      taggedUsers: TAGGED_USERS_SELECT,
      likes: {
        orderBy: { createdAt: "desc" },
        take: 3,
        select: {
          user: {
            select: {
              id: true,
              name: true,
              username: true,
              role: true,
              profilePhotoUrl: true,
            },
          },
        },
      },
    },
  });

  if (!post) {
    return NextResponse.json(
      { error: "Postingan tidak ditemukan." },
      { status: 404 }
    );
  }

  const session = await getSession("CUSTOMER").catch(() => null);
  let viewerLiked = false;
  let viewerSaved = false;
  if (session?.sub) {
    const [like, savedIds] = await Promise.all([
      prisma.feedLike
        .findUnique({
          where: { userId_postId: { userId: session.sub, postId: post.id } },
          select: { userId: true },
        })
        .catch(() => null),
      getViewerSavedPostIds(session.sub, [post.id]).catch(
        () => new Set<string>()
      ),
    ]);
    viewerLiked = Boolean(like);
    viewerSaved = savedIds.has(post.id);
  }

  const playbackUrls = buildFeedVideoPlaybackUrls({
    videoUrl: post.videoUrl,
    videoGuid: post.videoGuid,
  });
  const authorDisplayName = brandDisplayName(post.author.role, post.author.name);
  const authorPhoto = brandPhotoUrl(
    post.author.role,
    post.author.profilePhotoUrl
  );
  const products = [
    ...post.taggedProducts,
    ...(post.product
      ? [
          {
            position: post.taggedProducts.length,
            promoPrice: null,
            product: post.product,
          },
        ]
      : []),
  ]
    .filter(
      (entry, index, all) =>
        all.findIndex(
          (candidate) => candidate.product.id === entry.product.id
        ) === index
    )
    .map((entry) => {
      const discount = resolveFeedProductDiscount(
        entry.product,
        now,
        entry.promoPrice
      );
      return {
        ...entry.product,
        discountPrice: discount.discountPrice,
        discountSource: discount.discountSource,
        avgRating: Number(entry.product.avgRating ?? 0),
        promoPrice: entry.promoPrice,
        position: entry.position,
        flashSaleEndsAt: undefined,
        discountItems: undefined,
      };
    });

  return NextResponse.json({
    id: post.id,
    shareVersion: buildFeedShareVersion(post),
    kind: post.kind,
    title: post.title,
    description: post.description,
    thumbnailUrl: signBunnyUrl(post.thumbnailUrl) ?? null,
    thumbnailBlurhash: post.thumbnailBlurhash,
    videoUrl: playbackUrls.videoUrl,
    videoDataSaverUrl: playbackUrls.videoDataSaverUrl,
    videoDurationSec: post.videoDurationSec,
    videoWidth: post.videoWidth,
    videoHeight: post.videoHeight,
    ...feedAccessibilityPayload(post, signBunnyUrl),
    createdAt: post.createdAt.toISOString(),
    likeCount: post.likeCount,
    commentCount: post.commentCount,
    viewCount: post.viewCount,
    viewerLiked,
    viewerSaved,
    products,
    taggedProducts: products,
    taggedUsers: serializeTaggedUsers(
      post.taggedUsers,
      new Map(post.media.map((m, index) => [m.id, index]))
    ),
    author: {
      id: post.author.id,
      // Akun official (admin) → brand name + foto null (klien render logo).
      name: authorDisplayName,
      username: post.author.username,
      role: post.author.role === "ADMIN" ? "ADMIN" : "CUSTOMER",
      profilePhotoUrl: authorPhoto,
    },
    media: post.media.map((m) => {
      const mediaPlaybackUrls = buildFeedVideoPlaybackUrls({ videoUrl: m.url });
      return {
        id: m.id,
        url: mediaPlaybackUrls.videoUrl ?? m.url,
        ...(m.mediaType === "video"
          ? { videoDataSaverUrl: mediaPlaybackUrls.videoDataSaverUrl }
          : {}),
        thumbnailUrl: signBunnyUrl(m.thumbnailUrl) ?? null,
        mediaType: m.mediaType,
        width: m.width,
        height: m.height,
        altText: m.altText,
      };
    }),
    recentLikers: post.likes.map((l) => ({
      id: l.user.id,
      name: brandDisplayName(l.user.role, l.user.name),
      username: l.user.username,
      role: l.user.role === "ADMIN" ? "ADMIN" : "CUSTOMER",
      profilePhotoUrl: brandPhotoUrl(l.user.role, l.user.profilePhotoUrl),
      avatarUrl: brandPhotoUrl(l.user.role, l.user.profilePhotoUrl),
    })),
  });
}

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
 *     videoAltText?: string | null,
 *     hasAudio?: boolean | null,
 *     subtitleUrl?: string | null,
 *     subtitleLanguage?: string | null,
 *     media?: Array<{ id: string, altText: string | null }>,
 *   }
 */
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  // Try ADMIN session first, fallback CUSTOMER. Same pattern as upload-url
  // (lihat lib/auth.ts cookie priority bug).
  const session = (await getSession("ADMIN")) ?? (await getSession("CUSTOMER"));
  if (!session) {
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const isAdmin = session.role === "ADMIN";

  // Cari post — customer boleh edit OWN user-generated post yang visible
  // di "My Posts". Community video lama pakai COMMUNITY, flow foto baru
  // pakai PHOTO_CAROUSEL; keduanya harus bisa edit caption.
  const post = await prisma.feedPost.findFirst({
    where: {
      id: postId,
      authorId: session.sub,
      deletedAt: null,
      ...(isAdmin
        ? { authorRole: "ADMIN" }
        : {
            authorRole: "CUSTOMER",
            kind: { in: ["COMMUNITY", "PHOTO_CAROUSEL"] },
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
      media: { select: { id: true } },
    },
  });

  if (!post) {
    return NextResponse.json(
      { error: "Post tidak ditemukan" },
      { status: 404 }
    );
  }

  const body = (await request.json().catch(() => ({}))) as {
    title?: string;
    description?: string | null;
    petType?: string | null;
    productIds?: unknown;
    // Per-product promo pricing untuk video PROMO (admin only).
    // Map productId → promoPrice (null = clear discount).
    productPromos?: Record<string, number | null>;
    // Legacy admin-only fields (single promo) — backward compat.
    promoOriginalPrice?: number | null;
    promoDiscountPrice?: number | null;
    videoAltText?: string | null;
    hasAudio?: boolean | null;
    subtitleUrl?: string | null;
    subtitleLanguage?: string | null;
    media?: unknown;
  };

  const accessibility = parseFeedAccessibilityMetadata(
    body as Record<string, unknown>,
    { partial: true }
  );
  if (!accessibility.ok) {
    return NextResponse.json({ error: accessibility.error }, { status: 400 });
  }

  // Validate fields
  const updates: {
    title?: string;
    description?: string | null;
    productId?: string | null;
    status?: typeof post.status;
    promoOriginalPrice?: number | null;
    promoDiscountPrice?: number | null;
    videoAltText?: string | null;
    hasAudio?: boolean | null;
    subtitleUrl?: string | null;
    subtitleLanguage?: string | null;
  } = { ...accessibility.data };

  let mediaAltTextUpdates: Array<{
    id: string;
    altText: string | null;
  }> | null = null;
  if (typeof body.media !== "undefined") {
    if (!Array.isArray(body.media) || body.media.length > 8) {
      return NextResponse.json(
        { error: "Media harus berupa array maksimal 8 item." },
        { status: 400 }
      );
    }

    const ownedMediaIds = new Set(post.media.map((item) => item.id));
    const seenMediaIds = new Set<string>();
    mediaAltTextUpdates = [];
    for (const [index, item] of body.media.entries()) {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        return NextResponse.json(
          { error: `Media ${index + 1} tidak valid.` },
          { status: 400 }
        );
      }
      const media = item as Record<string, unknown>;
      const mediaId = typeof media.id === "string" ? media.id.trim() : "";
      if (
        !mediaId ||
        !ownedMediaIds.has(mediaId) ||
        seenMediaIds.has(mediaId)
      ) {
        return NextResponse.json(
          { error: `Media ${index + 1} tidak ditemukan atau duplikat.` },
          { status: 400 }
        );
      }
      const altText = parseFeedAltText(
        media.altText ?? null,
        `Alt text media ${index + 1}`
      );
      if (!altText.ok) {
        return NextResponse.json({ error: altText.error }, { status: 400 });
      }
      seenMediaIds.add(mediaId);
      mediaAltTextUpdates.push({ id: mediaId, altText: altText.data });
    }
  }

  // Admin promo pricing — cuma valid kalau post kind=PROMO + admin session.
  if (isAdmin && post.kind === "PROMO") {
    if (typeof body.promoOriginalPrice !== "undefined") {
      const v = body.promoOriginalPrice;
      updates.promoOriginalPrice =
        v === null ? null : Number.isFinite(Number(v)) ? Number(v) : null;
    }
    if (typeof body.promoDiscountPrice !== "undefined") {
      const v = body.promoDiscountPrice;
      updates.promoDiscountPrice =
        v === null ? null : Number.isFinite(Number(v)) ? Number(v) : null;
    }
  }

  if (typeof body.title === "string") {
    const t = body.title.trim();
    if (t.length === 0) {
      // Caption dikosongkan — simpan string kosong (kolom NOT NULL tetap
      // valid). JANGAN pakai placeholder "Postingan baru": post tanpa caption
      // harus tampil polos tanpa baris caption/username (paritas IG).
      updates.title = "";
    } else if (t.length > MAX_TITLE_LENGTH) {
      return NextResponse.json(
        { error: `Judul max ${MAX_TITLE_LENGTH} karakter.` },
        { status: 400 }
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
        { status: 400 }
      );
    }
    composedDescription = desc;
  }
  // Customer: ada petType → re-compose description dengan "Info peliharaan"
  if (!isAdmin && typeof body.petType !== "undefined") {
    const petType = body.petType === null ? "" : String(body.petType).trim();
    const baseDesc =
      composedDescription !== undefined ? composedDescription ?? "" : "";
    const petInfo = petType ? `Info peliharaan: ${petType}` : "";
    const finalDesc = [baseDesc, petInfo].filter(Boolean).join("\n\n") || null;
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
        { status: 400 }
      );
    }
    newProductIds = unique;
    // Update FeedPost.productId ke primary (productIds[0]) supaya legacy
    // single-product display + product page query tetap work.
    updates.productId = unique[0] ?? null;
  }

  if (newProductIds !== null && newProductIds.length > 0) {
    const products = await prisma.product.findMany({
      where: { id: { in: newProductIds } },
      select: { id: true, isActive: true },
    });
    if (products.length !== newProductIds.length) {
      return NextResponse.json(
        { error: "Produk tidak ditemukan." },
        { status: 404 }
      );
    }
    if (!isAdmin && products.some((product) => !product.isActive)) {
      return NextResponse.json(
        { error: "Produk tidak aktif, tidak bisa di-tag." },
        { status: 400 }
      );
    }

    if (!isAdmin) {
      const verifiedPurchases = await prisma.orderItem.findMany({
        where: {
          productId: { in: newProductIds },
          order: {
            userId: session.sub,
            paymentStatus: "PAID",
            status: "DELIVERED",
          },
        },
        select: { productId: true },
        distinct: ["productId"],
      });
      if (verifiedPurchases.length !== newProductIds.length) {
        return NextResponse.json(
          {
            error:
              "Produk yang di-tag harus berasal dari riwayat pembelian yang sudah diterima.",
          },
          { status: 403 }
        );
      }
    }
  }

  // Customer edit re-trigger moderation HANYA untuk video (kind bukan
  // PHOTO_CAROUSEL). Foto/carousel yang sudah ACTIVE tetap ACTIVE saat
  // di-edit — dipercaya, tidak perlu review ulang. Sinkron dgn sisi Flutter
  // (MemberPostEditScreen: notice + optimistic status video-only).
  if (editReTriggersModeration({ isAdmin, status: post.status, kind: post.kind })) {
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
            // Pre-fill promoPrice langsung saat replace, supaya admin yang
            // submit productIds + productPromos di 1 PATCH tidak butuh 2
            // round trip. Null = no discount for that product.
            promoPrice:
              isAdmin && body.productPromos && productId in body.productPromos
                ? body.productPromos[productId] === null
                  ? null
                  : Number.isFinite(Number(body.productPromos[productId]))
                  ? Number(body.productPromos[productId])
                  : null
                : null,
          })),
          skipDuplicates: true,
        });
      }
    }

    // Per-product promo pricing — admin only. Update existing
    // FeedPostProduct rows tanpa replace (kalau productIds tidak ikut
    // di-update). Iterate kecil (max 5 produk) — pakai updateMany
    // satu-satu supaya kena composite (feedPostId, productId).
    if (isAdmin && body.productPromos && newProductIds === null) {
      for (const [productId, rawPromo] of Object.entries(body.productPromos)) {
        const promoPrice =
          rawPromo === null
            ? null
            : Number.isFinite(Number(rawPromo))
            ? Number(rawPromo)
            : null;
        await tx.feedPostProduct.updateMany({
          where: { feedPostId: post.id, productId },
          data: { promoPrice },
        });
      }
    }

    if (mediaAltTextUpdates !== null) {
      for (const media of mediaAltTextUpdates) {
        await tx.feedMedia.updateMany({
          where: { id: media.id, postId: post.id },
          data: { altText: media.altText },
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
  { params }: { params: Promise<{ id: string }> }
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

  // Select juga videoUrl / thumbnailUrl / videoGuid + media supaya bisa
  // cleanup Bunny + UploadThing asset setelah soft-delete commit.
  // Sebelumnya cuma ambil id+status — bug: user delete post tapi video di
  // Bunny tetap accumulate storage selamanya.
  //
  // Allow kedua kind user-generated: COMMUNITY (video) + PHOTO_CAROUSEL.
  // Sebelumnya filter `kind: "COMMUNITY"` aja → user gak bisa hapus post
  // foto carousel sendiri (visible bug post "asiong asiong" yang ke-stuck).
  const post = await prisma.feedPost.findFirst({
    where: {
      id: postId,
      authorId: session.sub,
      authorRole: "CUSTOMER",
      kind: { in: ["COMMUNITY", "PHOTO_CAROUSEL"] },
      deletedAt: null,
      status: { in: [...MY_FEED_VISIBLE_STATUSES] },
    },
    select: {
      id: true,
      status: true,
      videoUrl: true,
      thumbnailUrl: true,
      videoGuid: true,
      // Untuk PHOTO_CAROUSEL — semua FeedMedia rows perlu di-cleanup di
      // UploadThing (1-8 foto per post). Pakai uploadthingKey kalau ada.
      media: {
        select: { url: true, uploadthingKey: true },
      },
    },
  });

  if (!post) {
    return NextResponse.json(
      { error: "Post tidak ditemukan" },
      { status: 404 }
    );
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
  // auto-generated) + UploadThing asset (legacy video + PHOTO_CAROUSEL
  // media). Via `after()` (bukan `void`) — void promise bisa dibekukan
  // Vercel sebelum jalan → orphan asset terus menagih storage; after()
  // dijamin eksekusi tanpa menahan response delete. Kalau Bunny
  // unreachable, soft-delete tetap commit; weekly storage GC cron
  // (/api/cron/feed-storage-gc) catch orphan nanti.
  after(() =>
    deleteFeedAssets({
      videoUrl: post.videoUrl,
      thumbnailUrl: post.thumbnailUrl,
      videoGuid: post.videoGuid,
      mediaItems: post.media,
      context: `user-delete ${postId}`,
    })
  );

  return NextResponse.json({ ok: true });
}
