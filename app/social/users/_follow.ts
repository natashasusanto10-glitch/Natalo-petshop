/**
 * Social follow/unfollow shared helpers — single source of truth.
 *
 * History: pernah ada NestJS microservice (`social_service/`) yang
 * mirror logic file ini lewat `SOCIAL_API_BASE_URL` dart-define di
 * Flutter. Dual implementation di-kill May 2026 karena cost maintenance
 * (sync 2 file setiap perubahan, risiko drift schema Prisma) melebihi
 * manfaatnya — Nest service belum aktif serve traffic, semua follow
 * traffic tetap ke Vercel Next.js. Kalau ke depan ada trigger nyata
 * (Vercel cost spike dari social traffic, fitur real-time chat/live
 * notif, atau timeout di endpoint social), resurrect Nest dari branch
 * `codex/deploy-social-routes` yang preserve di git history.
 */
import { NextResponse } from "next/server";
import { Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

type ListQuery = {
  cursor?: string | null;
  limit?: string | null;
};

class SocialHttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export async function requireSocialUserId() {
  const session = await getSession("CUSTOMER");
  if (!session?.sub) {
    throw new SocialHttpError(401, "Login dulu untuk akses fitur sosial.");
  }
  return session.sub;
}

export async function followUser(viewerUserId: string, targetUserId: string) {
  assertDifferentUsers(viewerUserId, targetUserId);

  const result = await prisma.$transaction(async (tx) => {
    const [target, actor] = await Promise.all([
      tx.user.findUnique({
        where: { id: targetUserId },
        select: {
          id: true,
          followersCount: true,
          followingCount: true,
        },
      }),
      tx.user.findUnique({
        where: { id: viewerUserId },
        select: { id: true, name: true, username: true },
      }),
    ]);

    if (!target) throw new SocialHttpError(404, "User tidak ditemukan.");
    if (!actor) throw new SocialHttpError(404, "User login tidak ditemukan.");

    const created = await tx.userFollow.createMany({
      data: [
        {
          followerId: viewerUserId,
          followingId: targetUserId,
        },
      ],
      skipDuplicates: true,
    });

    if (created.count === 0) {
      return {
        changed: false,
        isFollowing: true,
        followersCount: target.followersCount,
        followingCount: target.followingCount,
      };
    }

    const [updatedTarget] = await Promise.all([
      tx.user.update({
        where: { id: targetUserId },
        data: { followersCount: { increment: 1 } },
        select: { followersCount: true, followingCount: true },
      }),
      tx.user.update({
        where: { id: viewerUserId },
        data: { followingCount: { increment: 1 } },
        select: { id: true },
      }),
      tx.announcement.create({
        data: {
          title: "Pengikut baru",
          body: `${actor.username || actor.name} mulai mengikuti kamu.`,
          url: actor.username ? `/u/${actor.username}` : null,
          segment: "all",
          type: "social",
          source: "social",
          eventType: "user_followed",
          ctaLabel: "Lihat Profil",
          publishedAt: new Date(),
          targetUserId,
        },
      }),
    ]);

    return {
      changed: true,
      isFollowing: true,
      followersCount: updatedTarget.followersCount,
      followingCount: updatedTarget.followingCount,
    };
  });

  return stateResponse(targetUserId, false, result);
}

export async function unfollowUser(viewerUserId: string, targetUserId: string) {
  assertDifferentUsers(viewerUserId, targetUserId);

  const result = await prisma.$transaction(async (tx) => {
    const target = await tx.user.findUnique({
      where: { id: targetUserId },
      select: {
        id: true,
        followersCount: true,
        followingCount: true,
      },
    });

    if (!target) throw new SocialHttpError(404, "User tidak ditemukan.");

    const deleted = await tx.userFollow.deleteMany({
      where: {
        followerId: viewerUserId,
        followingId: targetUserId,
      },
    });

    if (deleted.count === 0) {
      return {
        changed: false,
        isFollowing: false,
        followersCount: target.followersCount,
        followingCount: target.followingCount,
      };
    }

    const [updatedTarget] = await Promise.all([
      tx.user.update({
        where: { id: targetUserId },
        data: { followersCount: { decrement: 1 } },
        select: { followersCount: true, followingCount: true },
      }),
      tx.user.update({
        where: { id: viewerUserId },
        data: { followingCount: { decrement: 1 } },
        select: { id: true },
      }),
    ]);

    return {
      changed: true,
      isFollowing: false,
      followersCount: updatedTarget.followersCount,
      followingCount: updatedTarget.followingCount,
    };
  });

  return stateResponse(targetUserId, false, result);
}

export async function getFollowState(viewerUserId: string, targetUserId: string) {
  const target = await prisma.user.findUnique({
    where: { id: targetUserId },
    select: {
      id: true,
      followersCount: true,
      followingCount: true,
    },
  });
  if (!target) throw new SocialHttpError(404, "User tidak ditemukan.");

  const isSelf = viewerUserId === targetUserId;
  const follow = isSelf
    ? null
    : await prisma.userFollow.findUnique({
        where: {
          followerId_followingId: {
            followerId: viewerUserId,
            followingId: targetUserId,
          },
        },
        select: { id: true },
      });

  return stateResponse(targetUserId, isSelf, {
    changed: false,
    isFollowing: Boolean(follow),
    followersCount: target.followersCount,
    followingCount: target.followingCount,
  });
}

export async function listFollowers(targetUserId: string, query: ListQuery) {
  await assertTargetExists(targetUserId);
  const limit = normalizeLimit(query.limit);
  const rows = await prisma.userFollow.findMany({
    where: { followingId: targetUserId },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: limit + 1,
    ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
    include: {
      follower: {
        select: publicUserSelect,
      },
    },
  });

  const hasMore = rows.length > limit;
  const sliced = hasMore ? rows.slice(0, limit) : rows;
  return {
    ok: true,
    items: sliced.map((row) => mapPublicUser(row.follower)),
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
  };
}

export async function listFollowing(targetUserId: string, query: ListQuery) {
  await assertTargetExists(targetUserId);
  const limit = normalizeLimit(query.limit);
  const rows = await prisma.userFollow.findMany({
    where: { followerId: targetUserId },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: limit + 1,
    ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
    include: {
      following: {
        select: publicUserSelect,
      },
    },
  });

  const hasMore = rows.length > limit;
  const sliced = hasMore ? rows.slice(0, limit) : rows;
  return {
    ok: true,
    items: sliced.map((row) => mapPublicUser(row.following)),
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
  };
}

export function socialJson(data: unknown, init?: ResponseInit) {
  return NextResponse.json(data, init);
}

export function socialError(error: unknown) {
  if (error instanceof SocialHttpError) {
    return NextResponse.json(
      { ok: false, message: error.message },
      { status: error.status },
    );
  }

  console.error("[social]", error);
  return NextResponse.json(
    { ok: false, message: "Gagal memproses fitur sosial." },
    { status: 500 },
  );
}

async function assertTargetExists(targetUserId: string) {
  const target = await prisma.user.findUnique({
    where: { id: targetUserId },
    select: { id: true },
  });
  if (!target) throw new SocialHttpError(404, "User tidak ditemukan.");
}

function assertDifferentUsers(viewerUserId: string, targetUserId: string) {
  if (viewerUserId === targetUserId) {
    throw new SocialHttpError(400, "Tidak bisa follow akun sendiri.");
  }
}

function stateResponse(
  targetUserId: string,
  isSelf: boolean,
  state: {
    changed: boolean;
    isFollowing: boolean;
    followersCount: number;
    followingCount: number;
  },
) {
  return {
    ok: true,
    targetUserId,
    isSelf,
    ...state,
  };
}

const publicUserSelect = {
  id: true,
  name: true,
  username: true,
  profilePhotoUrl: true,
  bio: true,
  followersCount: true,
  followingCount: true,
} satisfies Prisma.UserSelect;

function mapPublicUser(
  user: Prisma.UserGetPayload<{ select: typeof publicUserSelect }>,
) {
  return {
    id: user.id,
    name: user.name,
    username: user.username,
    profilePhotoUrl: user.profilePhotoUrl,
    bio: user.bio,
    followersCount: user.followersCount,
    followingCount: user.followingCount,
  };
}

function normalizeLimit(raw?: string | null) {
  const parsed = Number(raw ?? DEFAULT_LIMIT);
  if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_LIMIT;
  return Math.min(MAX_LIMIT, Math.max(1, Math.floor(parsed)));
}
