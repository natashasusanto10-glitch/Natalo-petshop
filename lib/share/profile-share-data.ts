import type { Metadata } from "next";

import { prisma } from "@/lib/prisma";
import {
  brandDisplayName,
  brandPhotoUrl,
  isAdminRole,
} from "@/lib/social/brand-user";
import { normalizeUsername, resolveUserByUsername } from "@/lib/username";

import { buildShareVersion, stripEphemeralUrlQuery } from "./share-version";

const BRAND_NAME = "Natalo Petshop";
const OFFICIAL_AVATAR_PATH = "/logo.png";

type ResolvedPublicUser = NonNullable<Awaited<ReturnType<typeof resolveUserByUsername>>>;
type ProfileRepository = Pick<typeof prisma, "feedPost">;

export type ProfileShareSource = Pick<
  ResolvedPublicUser,
  "id" | "name" | "username" | "profilePhotoUrl" | "bio" | "followersCount" | "followingCount" | "role"
> & {
  postCount: number;
};

export type PublicShareProfile = {
  id: string;
  username: string;
  displayName: string;
  avatarUrl: string;
  bio: string | null;
  isOfficial: boolean;
  postCount: number;
  followersCount: number;
  followingCount: number;
  shareVersion: string;
};

export function sanitizePublicProfileBio(value: string | null | undefined) {
  const clean = (value ?? "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!clean) return null;
  return clean.length > 120 ? `${clean.slice(0, 119).trimEnd()}…` : clean;
}

function sanitizeDisplayName(value: string | null | undefined) {
  const clean = (value ?? "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return clean.slice(0, 80);
}

function nonNegative(value: number) {
  return Math.max(0, Math.trunc(value));
}

export function buildPublicShareProfile(
  user: ProfileShareSource | null,
): PublicShareProfile | null {
  if (!user) return null;

  const username = normalizeUsername(user.username ?? "");
  if (!username) return null;
  const isOfficial = isAdminRole(user.role);
  const displayName = sanitizeDisplayName(brandDisplayName(user.role, user.name)) || BRAND_NAME;
  const avatarUrl = isOfficial
    ? OFFICIAL_AVATAR_PATH
    : stripEphemeralUrlQuery(brandPhotoUrl(user.role, user.profilePhotoUrl)) || OFFICIAL_AVATAR_PATH;
  // ADMIN represents the official brand. Its staff profile fields are not
  // public brand copy and must not reach crawler metadata.
  const bio = isOfficial ? null : sanitizePublicProfileBio(user.bio);
  const postCount = nonNegative(user.postCount);
  const followersCount = nonNegative(user.followersCount);
  const followingCount = nonNegative(user.followingCount);

  return {
    id: user.id,
    username,
    displayName,
    avatarUrl,
    bio,
    isOfficial,
    postCount,
    followersCount,
    followingCount,
    shareVersion: buildShareVersion([
      username,
      displayName,
      avatarUrl,
      bio,
      isOfficial,
      postCount,
      followersCount,
      followingCount,
    ]),
  };
}

/** Resolves the same public profile identity as `/u/[username]`. */
export async function getPublicShareProfile(
  rawUsername: string,
  resolver: typeof resolveUserByUsername = resolveUserByUsername,
  repository: ProfileRepository = prisma,
): Promise<PublicShareProfile | null> {
  const requestedUsername = normalizeUsername(rawUsername);
  if (!requestedUsername) return null;
  const user = await resolver(requestedUsername);
  if (!user) return null;

  const postCount = await repository.feedPost.count({
    where: {
      authorId: user.id,
      kind: { in: ["COMMUNITY", "PHOTO_CAROUSEL"] },
      status: "ACTIVE",
      deletedAt: null,
    },
  });
  return buildPublicShareProfile({ ...user, postCount });
}

function publicUrl(siteUrl: string, path: string) {
  return new URL(path, siteUrl).toString();
}

export function buildUnavailableProfileShareMetadata(): Metadata {
  return {
    title: "Profil tidak ditemukan | Natalo Petshop",
    description: "Profil yang Anda cari tidak tersedia.",
    robots: { index: false, follow: false },
  };
}

export function buildProfileShareMetadata(profile: PublicShareProfile, siteUrl: string): Metadata {
  const path = `/u/${encodeURIComponent(profile.username)}`;
  const canonical = publicUrl(siteUrl, path);
  const title = `${profile.displayName} (@${profile.username}) di Natalo`;
  const description =
    profile.bio ?? `Lihat profil dan postingan ${profile.displayName} di Natalo.`;
  const image = publicUrl(
    siteUrl,
    `/api/share/og/profile/${encodeURIComponent(profile.username)}?v=${encodeURIComponent(profile.shareVersion)}`,
  );

  return {
    title,
    description,
    alternates: { canonical },
    robots: { index: true, follow: true },
    openGraph: {
      type: "profile",
      title,
      description,
      url: canonical,
      siteName: BRAND_NAME,
      images: [{ url: image, width: 1200, height: 630, alt: profile.displayName }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [image],
    },
  };
}
