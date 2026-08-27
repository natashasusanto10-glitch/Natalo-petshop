/**
 * /u/{username} — Public profile page.
 *
 * Server-rendered untuk:
 *   1. SEO + OG meta tags (link share di WhatsApp/IG dapat preview rapi)
 *   2. iOS Universal Link target — kalau Natalo app ter-install,
 *      iOS handle URL ini → buka app native; kalau gak, browser
 *      tampilkan halaman ini.
 *   3. Android App Link target — sama dengan iOS via assetlinks.json.
 *
 * Logic resolve username support 30-day grace period — kalau handle
 * baru diganti, link lama tetap valid sementara (anti broken share).
 */
import type { Metadata } from "next";
import Image from "next/image";
import { notFound } from "next/navigation";

import OpenInAppButtons from "@/components/OpenInAppButtons";
import StickyOpenInAppBar from "@/components/StickyOpenInAppBar";
import { prisma } from "@/lib/prisma";
import {
  buildPublicProfilePageViewModel,
  buildProfileShareMetadata,
  buildUnavailableProfileShareMetadata,
  getPublicShareProfile,
} from "@/lib/share/profile-share-data";

const siteUrl =
  process.env.NEXT_PUBLIC_SITE_URL || "https://www.natalopetshop.com";

type PageProps = {
  params: Promise<{ username: string }>;
};

// The metadata carries an object version. Only the corresponding OG image is
// long-lived in the CDN cache, so a profile change cannot retain a stale card.
export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function generateMetadata({
  params,
}: PageProps): Promise<Metadata> {
  const { username } = await params;
  const profile = await getPublicShareProfile(username);
  if (!profile) return buildUnavailableProfileShareMetadata();
  return buildProfileShareMetadata(profile, siteUrl);
}

export default async function PublicProfilePage({ params }: PageProps) {
  const { username } = await params;
  const profile = await getPublicShareProfile(username);
  if (!profile) notFound();
  const view = buildPublicProfilePageViewModel(profile);

  const [likedCount, posts] = await Promise.all([
    prisma.feedLike.count({ where: { userId: view.id } }),
    prisma.feedPost.findMany({
      where: {
        authorId: view.id,
        kind: { in: ["COMMUNITY", "PHOTO_CAROUSEL"] },
        status: "ACTIVE",
        deletedAt: null,
      },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: 18,
      select: {
        id: true,
        kind: true,
        thumbnailUrl: true,
        videoDurationSec: true,
        likeCount: true,
        media: {
          orderBy: { sortOrder: "asc" },
          take: 1,
          select: { url: true, thumbnailUrl: true },
        },
      },
    }),
  ]);

  const handle = view.username;
  const initial = view.displayName.trim().charAt(0).toUpperCase() || "N";

  return (
    // pb-24 di layar kecil: ruang untuk StickyOpenInAppBar supaya baris
    // terakhir grid postingan tidak tertutup bar saat digulir mentok.
    <div className="mx-auto min-h-screen w-full max-w-3xl px-4 pb-24 pt-6 sm:px-6 md:pb-16">
      {/* Header */}
      <header className="flex flex-col items-start gap-5 sm:flex-row sm:items-center">
        <div className="relative h-24 w-24 shrink-0 overflow-hidden rounded-full bg-gradient-to-br from-blue-100 to-blue-200 ring-4 ring-white shadow-md sm:h-28 sm:w-28">
          {view.avatarUrl ? (
            <Image
              src={view.avatarUrl}
              alt={view.displayName}
              fill
              sizes="112px"
              className="object-cover"
              unoptimized
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center text-3xl font-black text-blue-700">
              {initial}
            </div>
          )}
        </div>
        <div className="flex-1">
          <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <h1 className="text-2xl font-black text-slate-900">
              {handle}
            </h1>
            {view.displayName !== view.username && (
              <span className="text-sm font-medium text-slate-500">
                {view.displayName}
              </span>
            )}
          </div>
          {view.bio && (
            <p className="mt-1.5 max-w-md text-sm text-slate-600">
              {view.bio}
            </p>
          )}
          <dl className="mt-3 flex gap-6 text-sm">
            <div>
              <dd className="font-black text-slate-900">{view.postCount}</dd>
              <dt className="text-slate-500">Postingan</dt>
            </div>
            <div>
              <dd className="font-black text-slate-900">{likedCount}</dd>
              <dt className="text-slate-500">Disukai</dt>
            </div>
          </dl>
        </div>
      </header>

      {/* CTA — buka di app */}
      <div className="mt-6 rounded-2xl border border-blue-100 bg-blue-50/70 p-4">
        <p className="text-sm font-semibold text-blue-900">
          Buka di aplikasi Natalo Petshop untuk pengalaman lebih baik —
          like, komentar, dan ikuti {handle}.
        </p>
        <OpenInAppButtons path={`/u/${encodeURIComponent(view.username)}`} />
      </div>

      {/* Postingan grid */}
      <section className="mt-8">
        <h2 className="mb-3 text-sm font-black uppercase tracking-wide text-slate-500">
          Postingan
        </h2>
        {posts.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-slate-200 bg-slate-50 px-4 py-12 text-center text-sm text-slate-500">
            Belum ada postingan.
          </div>
        ) : (
          <div className="grid grid-cols-3 gap-1 sm:gap-2">
            {posts.map((p) => {
              const thumb =
                p.thumbnailUrl ??
                p.media[0]?.thumbnailUrl ??
                p.media[0]?.url ??
                null;
              return (
                <div
                  key={p.id}
                  className="relative aspect-square overflow-hidden rounded-md bg-slate-100"
                >
                  {thumb ? (
                    <Image
                      src={thumb}
                      alt=""
                      fill
                      sizes="(max-width: 640px) 33vw, 200px"
                      className="object-cover"
                      unoptimized
                    />
                  ) : (
                    <div className="flex h-full w-full items-center justify-center text-xs text-slate-400">
                      Foto
                    </div>
                  )}
                  {p.kind === "COMMUNITY" && (
                    <div className="absolute right-1.5 top-1.5 rounded-full bg-black/55 p-1.5">
                      <svg
                        viewBox="0 0 24 24"
                        className="h-3 w-3 fill-white"
                        aria-hidden
                      >
                        <path d="M8 5v14l11-7z" />
                      </svg>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </section>
      <StickyOpenInAppBar path={`/u/${encodeURIComponent(view.username)}`} />
    </div>
  );
}
