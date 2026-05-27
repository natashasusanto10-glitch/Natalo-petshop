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

const VISIBLE_KINDS: FeedPostKind[] = [
  "COMMUNITY",
  "PHOTO_CAROUSEL",
];

const MAX_LIMIT = 50;
const DEFAULT_LIMIT = 20;

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ username: string }> },
) {
  const { username } = await params;
  const target = await resolveUserByUsername(username);
  if (!target) {
    return NextResponse.json(
      { error: "USER_NOT_FOUND", message: "User tidak ditemukan." },
      { status: 404 },
    );
  }

  const session = await getSession("CUSTOMER");
  const viewerUserId = session?.sub ?? null;
  const isOwner = viewerUserId === target.id;

  const cursor = request.nextUrl.searchParams.get("cursor") || null;
  const rawLimit = Number(
    request.nextUrl.searchParams.get("limit") ?? `${DEFAULT_LIMIT}`,
  );
  const limit =
    Number.isFinite(rawLimit) && rawLimit > 0
      ? Math.min(MAX_LIMIT, Math.max(1, Math.floor(rawLimit)))
      : DEFAULT_LIMIT;

  const [rawPosts, totalCount, likedCount, viewerFollow] = await Promise.all([
    prisma.feedPost.findMany({
      where: {
        authorId: target.id,
        kind: { in: VISIBLE_KINDS },
        status: "ACTIVE",
        deletedAt: null,
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
      },
    }),
    // Total post count untuk header stats.
    prisma.feedPost.count({
      where: {
        authorId: target.id,
        kind: { in: VISIBLE_KINDS },
        status: "ACTIVE",
        deletedAt: null,
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

  return NextResponse.json({
    user: {
      id: target.id,
      name: target.name,
      username: target.username,
      profilePhotoUrl: target.profilePhotoUrl,
      bio: target.bio,
      memberSince: target.createdAt.toISOString(),
    },
    stats: {
      postCount: totalCount,
      likedCount,
      followersCount: target.followersCount,
      followingCount: target.followingCount,
    },
    isOwner,
    isFollowing: Boolean(viewerFollow),
    items: sliced.map((p) => ({
      id: p.id,
      kind: p.kind,
      title: p.title,
      description: p.description,
      thumbnailUrl: p.thumbnailUrl,
      videoUrl: p.videoUrl,
      videoDurationSec: p.videoDurationSec,
      videoWidth: p.videoWidth,
      videoHeight: p.videoHeight,
      createdAt: p.createdAt.toISOString(),
      likeCount: p.likeCount,
      commentCount: p.commentCount,
      viewCount: p.viewCount,
      media: p.media.map((m) => ({
        id: m.id,
        url: m.url,
        thumbnailUrl: m.thumbnailUrl,
        mediaType: m.mediaType,
        width: m.width,
        height: m.height,
      })),
    })),
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
  });
}
