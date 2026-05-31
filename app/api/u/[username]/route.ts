/**
 * GET /api/u/{username}?cursor=...&limit=20
 *
 * Public profile endpoint — return profile + paginated posts user.
 * Tidak butuh login. Dipakai oleh:
 *   - app/u/[username]/page.tsx (web profile page, SSR)
 *   - Flutter public_profile_screen (visit other user profile)
 *
 * Username resolution lewat lib/username.ts → resolveUserByUsername:
 *   - Current owner match (User.username)
 *   - Atau UsernameHistory 30-hari grace period match (anti-broken-link)
 *
 * Posts: filter status=ACTIVE only (public visibility) + sort
 * createdAt desc. Cursor-paginated supaya scroll infinite di Flutter
 * + web tab "Postingan" tidak nge-block dengan fetch all-at-once.
 *
 * Like state per-viewer: kalau session ada (viewer login), batch
 * resolve viewer's like state untuk batch ini → UI tampil heart
 * filled vs outline yang akurat.
 */
import { NextRequest, NextResponse } from "next/server";
import type { FeedPostKind } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { resolveUserByUsername } from "@/lib/username";
import { getSession } from "@/lib/auth";
import { signBunnyUrl } from "@/lib/feed/bunny";

// Postingan customer biasa: video komunitas + foto carousel.
const VISIBLE_KINDS: FeedPostKind[] = ["COMMUNITY", "PHOTO_CAROUSEL"];
// Postingan admin (akun official Natalo Petshop): video edukasi/jualan +
// promo + foto. Tanpa ini, grid profil admin selalu "0 Postingan" karena
// admin tidak pernah pakai kind COMMUNITY.
const ADMIN_VISIBLE_KINDS: FeedPostKind[] = [
  "VIDEO_ONLY",
  "VIDEO_PRODUCT",
  "PROMO",
  "PHOTO_CAROUSEL",
];

// Branding akun official — saat target.role ADMIN, tampilkan sebagai
// brand "Natalo Petshop" (BUKAN nama asli pemilik). Hide foto + bio
// pribadi (privacy), Flutter render badge official + logo brand.
const OFFICIAL_BRAND_NAME = "Natalo Petshop";
const OFFICIAL_BRAND_BIO = "Akun resmi Natalo Petshop & Aquarium 🐾";

const MAX_LIMIT = 50;
const DEFAULT_LIMIT = 20;

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ username: string }> }
) {
  const { username } = await params;
  const target = await resolveUserByUsername(username);
  if (!target) {
    return NextResponse.json(
      { error: "USER_NOT_FOUND", message: "User tidak ditemukan." },
      { status: 404 }
    );
  }

  const session = await getSession("CUSTOMER");
  const viewerUserId = session?.sub ?? null;
  const isOwner = viewerUserId === target.id;

  // Akun official (admin) → branding "Natalo Petshop" + tampilkan
  // postingan admin (ADMIN_VISIBLE_KINDS), bukan COMMUNITY/PHOTO user.
  const isOfficial = target.role === "ADMIN";
  const visibleKinds = isOfficial ? ADMIN_VISIBLE_KINDS : VISIBLE_KINDS;

  const cursor = request.nextUrl.searchParams.get("cursor") || null;
  const rawLimit = Number(
    request.nextUrl.searchParams.get("limit") ?? `${DEFAULT_LIMIT}`
  );
  const limit =
    Number.isFinite(rawLimit) && rawLimit > 0
      ? Math.min(MAX_LIMIT, Math.max(1, Math.floor(rawLimit)))
      : DEFAULT_LIMIT;

  const [rawPosts, totalCount, likedCount, viewerFollow] = await Promise.all([
    prisma.feedPost.findMany({
      where: {
        authorId: target.id,
        kind: { in: visibleKinds },
        status: "ACTIVE",
        deletedAt: null,
        // Mirror reels feed filter (lib/feed/queries.ts) — skip video yang
        // masih encoding di Bunny Stream. Tanpa filter ini: video baru
        // tampil dengan videoUrl=null + thumbnail saja → Flutter player
        // gagal load → "Video belum bisa diputar". Legacy UploadThing post
        // default 'ready' jadi tetap surface.
        encodingStatus: "ready",
      },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: limit + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      select: {
        id: true,
        kind: true,
        title: true,
        description: true,
        thumbnailUrl: true,
        videoUrl: true,
        videoDurationSec: true,
        videoWidth: true,
        videoHeight: true,
        createdAt: true,
        likeCount: true,
        commentCount: true,
        viewCount: true,
        media: {
          orderBy: { sortOrder: "asc" },
          select: {
            id: true,
            url: true,
            thumbnailUrl: true,
            mediaType: true,
            width: true,
            height: true,
          },
        },
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
    }),
    // Total post count untuk header stats. Konsisten dengan findMany —
    // post yang masih encoding tidak ikut count (kalau ikut, header
    // tampil "5 Postingan" tapi grid cuma show 4 → bingung user).
    prisma.feedPost.count({
      where: {
        authorId: target.id,
        kind: { in: visibleKinds },
        status: "ACTIVE",
        deletedAt: null,
        encodingStatus: "ready",
      },
    }),
    // Liked count — total likes yang user ini kasih ke feed posts.
    // Public stat (match IG/TikTok "Disukai" tab).
    prisma.feedLike.count({
      where: { userId: target.id },
    }),
    viewerUserId && !isOwner
      ? prisma.userFollow.findUnique({
          where: {
            followerId_followingId: {
              followerId: viewerUserId,
              followingId: target.id,
            },
          },
          select: { id: true },
        })
      : null,
  ]);

  const hasMore = rawPosts.length > limit;
  const sliced = hasMore ? rawPosts.slice(0, limit) : rawPosts;
  const viewerLikedIds =
    viewerUserId && sliced.length > 0
      ? new Set(
          (
            await prisma.feedLike.findMany({
              where: {
                userId: viewerUserId,
                postId: { in: sliced.map((p) => p.id) },
              },
              select: { postId: true },
            })
          ).map((like) => like.postId)
        )
      : new Set<string>();

  return NextResponse.json({
    user: {
      id: target.id,
      // Official → brand name "Natalo Petshop", hide nama asli pemilik +
      // foto/bio pribadi (privacy). Flutter render badge + logo brand.
      name: isOfficial ? OFFICIAL_BRAND_NAME : target.name,
      username: target.username,
      profilePhotoUrl: isOfficial ? null : target.profilePhotoUrl,
      bio: isOfficial ? OFFICIAL_BRAND_BIO : target.bio,
      memberSince: target.createdAt.toISOString(),
      isOfficial,
    },
    stats: {
      postCount: totalCount,
      likedCount,
      followersCount: target.followersCount,
      followingCount: target.followingCount,
    },
    isOwner,
    isOfficial,
    isFollowing: Boolean(viewerFollow),
    // Sign Bunny URLs supaya hotlink protection tidak return 401. Tanpa
    // signing thumbnailUrl video → CachedNetworkImage di grid public
    // profile dapat 401 → fallback ColoredBox abu-abu (terlihat tile
    // kosong dengan icon play). Tanpa signing videoUrl → player tidak
    // bisa fetch HLS playlist → "video tidak bisa diputar".
    // `signBunnyUrl` no-op untuk URL non-Bunny (UploadThing image
    // carousel return as-is), jadi aman apply ke semua URL.
    items: sliced.map((p) => ({
      id: p.id,
      kind: p.kind,
      title: p.title,
      description: p.description,
      thumbnailUrl: signBunnyUrl(p.thumbnailUrl) ?? null,
      videoUrl: signBunnyUrl(p.videoUrl) ?? null,
      videoDurationSec: p.videoDurationSec,
      videoWidth: p.videoWidth,
      videoHeight: p.videoHeight,
      createdAt: p.createdAt.toISOString(),
      likeCount: p.likeCount,
      commentCount: p.commentCount,
      viewCount: p.viewCount,
      viewerLiked: viewerLikedIds.has(p.id),
      recentLikers: p.likes.map((like) => ({
        id: like.user.id,
        name: like.user.name,
        username: like.user.username,
        role: like.user.role === "ADMIN" ? "ADMIN" : "CUSTOMER",
        profilePhotoUrl: like.user.profilePhotoUrl,
        avatarUrl: like.user.profilePhotoUrl,
      })),
      media: p.media.map((m) => ({
        id: m.id,
        url: signBunnyUrl(m.url) ?? m.url,
        thumbnailUrl: signBunnyUrl(m.thumbnailUrl) ?? null,
        mediaType: m.mediaType,
        width: m.width,
        height: m.height,
      })),
    })),
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
  });
}
