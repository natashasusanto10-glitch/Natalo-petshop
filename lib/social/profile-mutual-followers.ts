import type { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import {
  brandDisplayName,
  brandPhotoUrl,
  isAdminRole,
} from "@/lib/social/brand-user";

export type PublicMutualFollower = {
  id: string;
  name: string;
  username: string | null;
  profilePhotoUrl: string | null;
  isOfficial: boolean;
};

export type PublicMutualFollowerSummary = {
  items: PublicMutualFollower[];
  totalCount: number;
};

type MutualFollowerRow = {
  follower: {
    id: string;
    name: string | null;
    username: string | null;
    profilePhotoUrl: string | null;
    role: string | null;
  };
};

export type MutualFollowerDependencies = {
  findMany: (where: Prisma.UserFollowWhereInput) => Promise<MutualFollowerRow[]>;
  count: (where: Prisma.UserFollowWhereInput) => Promise<number>;
};

export type LoadMutualFollowersInput = {
  viewerUserId: string | null;
  targetUserId: string;
  isOwner: boolean;
};

const emptySummary = (): PublicMutualFollowerSummary => ({
  items: [],
  totalCount: 0,
});

const publicMutualFollowerName = (
  follower: MutualFollowerRow["follower"],
): string => {
  if (isAdminRole(follower.role)) {
    return brandDisplayName(follower.role, follower.name);
  }

  const name = follower.name?.trim();
  if (name) return name;

  const username = follower.username?.trim().replace(/^@+/, "").trim();
  if (username) return `@${username}`;

  return "Pengguna Natalo";
};

export function buildMutualFollowerWhere(
  viewerUserId: string,
  targetUserId: string,
): Prisma.UserFollowWhereInput {
  return {
    followingId: targetUserId,
    follower: {
      followers: {
        some: { followerId: viewerUserId },
      },
    },
  };
}

const defaultDependencies: MutualFollowerDependencies = {
  findMany: (where) =>
    prisma.userFollow.findMany({
      where,
      orderBy: [{ createdAt: "desc" }, { id: "asc" }],
      take: 3,
      select: {
        follower: {
          select: {
            id: true,
            name: true,
            username: true,
            profilePhotoUrl: true,
            role: true,
          },
        },
      },
    }),
  count: (where) => prisma.userFollow.count({ where }),
};

export async function loadMutualFollowers(
  input: LoadMutualFollowersInput,
  dependencies: MutualFollowerDependencies = defaultDependencies,
): Promise<PublicMutualFollowerSummary> {
  // Ala IG: "Diikuti oleh …" tampil di SEMUA profil (official maupun
  // user biasa) — cukup gate viewer login + bukan profil sendiri.
  if (!input.viewerUserId || input.isOwner) {
    return emptySummary();
  }
  const where = buildMutualFollowerWhere(
    input.viewerUserId,
    input.targetUserId,
  );
  try {
    const [rows, totalCount] = await Promise.all([
      dependencies.findMany(where),
      dependencies.count(where),
    ]);
    return {
      items: rows.map(({ follower }) => ({
        id: follower.id,
        name: publicMutualFollowerName(follower),
        username: follower.username,
        profilePhotoUrl: brandPhotoUrl(
          follower.role,
          follower.profilePhotoUrl,
        ),
        isOfficial: isAdminRole(follower.role),
      })),
      totalCount,
    };
  } catch {
    return emptySummary();
  }
}
