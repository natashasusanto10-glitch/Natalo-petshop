import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma.service";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

type ListQuery = {
  cursor?: string;
  limit?: string;
};

@Injectable()
export class FollowService {
  constructor(private readonly prisma: PrismaService) {}

  async follow(viewerUserId: string, targetUserId: string) {
    this.assertDifferentUsers(viewerUserId, targetUserId);

    const result = await this.prisma.$transaction(async (tx) => {
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

      if (!target) throw new NotFoundException("User tidak ditemukan.");
      if (!actor) throw new NotFoundException("User login tidak ditemukan.");

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

    return this.stateResponse(targetUserId, false, result);
  }

  async unfollow(viewerUserId: string, targetUserId: string) {
    this.assertDifferentUsers(viewerUserId, targetUserId);

    const result = await this.prisma.$transaction(async (tx) => {
      const target = await tx.user.findUnique({
        where: { id: targetUserId },
        select: {
          id: true,
          followersCount: true,
          followingCount: true,
        },
      });

      if (!target) throw new NotFoundException("User tidak ditemukan.");

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

    return this.stateResponse(targetUserId, false, result);
  }

  async getState(viewerUserId: string, targetUserId: string) {
    const target = await this.prisma.user.findUnique({
      where: { id: targetUserId },
      select: {
        id: true,
        followersCount: true,
        followingCount: true,
      },
    });
    if (!target) throw new NotFoundException("User tidak ditemukan.");

    const isSelf = viewerUserId === targetUserId;
    const follow = isSelf
      ? null
      : await this.prisma.userFollow.findUnique({
          where: {
            followerId_followingId: {
              followerId: viewerUserId,
              followingId: targetUserId,
            },
          },
          select: { id: true },
        });

    return this.stateResponse(targetUserId, isSelf, {
      changed: false,
      isFollowing: Boolean(follow),
      followersCount: target.followersCount,
      followingCount: target.followingCount,
    });
  }

  async listFollowers(targetUserId: string, query: ListQuery) {
    await this.assertTargetExists(targetUserId);
    const limit = normalizeLimit(query.limit);
    const rows = await this.prisma.userFollow.findMany({
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

  async listFollowing(targetUserId: string, query: ListQuery) {
    await this.assertTargetExists(targetUserId);
    const limit = normalizeLimit(query.limit);
    const rows = await this.prisma.userFollow.findMany({
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

  private async assertTargetExists(targetUserId: string) {
    const target = await this.prisma.user.findUnique({
      where: { id: targetUserId },
      select: { id: true },
    });
    if (!target) throw new NotFoundException("User tidak ditemukan.");
  }

  private assertDifferentUsers(viewerUserId: string, targetUserId: string) {
    if (viewerUserId === targetUserId) {
      throw new BadRequestException("Tidak bisa follow akun sendiri.");
    }
  }

  private stateResponse(
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

function normalizeLimit(raw?: string) {
  const parsed = Number(raw ?? DEFAULT_LIMIT);
  if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_LIMIT;
  return Math.min(MAX_LIMIT, Math.max(1, Math.floor(parsed)));
}
