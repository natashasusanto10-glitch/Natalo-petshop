import type { Metadata } from "next";
import Image from "next/image";
import { notFound } from "next/navigation";

import OpenInAppButtons from "@/components/OpenInAppButtons";
import StickyOpenInAppBar from "@/components/StickyOpenInAppBar";

import { getPublicShareFeedPost } from "@/lib/share/feed-share-data";
import {
  buildFeedShareMetadata,
  buildUnavailableFeedShareMetadata,
} from "@/lib/share/share-metadata";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "https://www.natalopetshop.com";

type PageProps = { params: Promise<{ id: string }> };

// The page HTML carries cache-busting metadata. Cache only the versioned OG image.
export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { id } = await params;
  const post = await getPublicShareFeedPost(id);
  if (!post) return buildUnavailableFeedShareMetadata();
  return buildFeedShareMetadata(post, siteUrl);
}

export default async function PublicFeedPostPage({ params }: PageProps) {
  const { id } = await params;
  const post = await getPublicShareFeedPost(id);
  if (!post) notFound();

  const headline = post.title.trim() || "Postingan Natalo";
  const caption = (post.description ?? "").replace(/\s+/g, " ").trim();

  return (
    // pb-24 di layar kecil: ruang untuk StickyOpenInAppBar supaya blok
    // tombol di akhir halaman tidak tertutup bar saat digulir mentok.
    <main className="mx-auto min-h-screen w-full max-w-xl bg-white px-4 pt-8 pb-24 sm:px-6 md:pb-8">
      <article>
        <header className="flex items-center gap-3">
          <div className="relative h-11 w-11 shrink-0 overflow-hidden rounded-full bg-blue-100">
            {post.author.photoUrl ? (
              <Image
                src={post.author.photoUrl}
                alt={post.author.displayName}
                fill
                sizes="44px"
                className="object-cover"
                unoptimized
              />
            ) : (
              <div className="flex h-full items-center justify-center font-bold text-blue-700">
                {post.author.displayName.charAt(0).toUpperCase() || "N"}
              </div>
            )}
          </div>
          <div>
            <p className="font-semibold text-slate-900">{post.author.displayName}</p>
            <p className="text-sm text-slate-500">Postingan di Natalo Petshop</p>
          </div>
        </header>

        <div className="relative mt-5 aspect-[9/16] overflow-hidden rounded-lg bg-slate-100">
          {post.posterUrl ? (
            <Image
              src={post.posterUrl}
              alt={headline}
              fill
              priority
              sizes="(max-width: 640px) 100vw, 576px"
              className="object-cover"
              unoptimized
            />
          ) : (
            <div className="flex h-full items-center justify-center text-sm text-slate-500">
              Media tidak tersedia
            </div>
          )}
        </div>

        <h1 className="mt-5 text-xl font-bold text-slate-900">{headline}</h1>
        {caption && <p className="mt-2 text-sm leading-6 text-slate-700">{caption}</p>}

        <section className="mt-6 border-t border-slate-100 pt-5">
          <p className="text-sm font-medium text-slate-700">Lihat postingan lengkap di aplikasi Natalo Petshop.</p>
          <OpenInAppButtons path={`/feed/${encodeURIComponent(post.id)}`} />
        </section>
      </article>
      <StickyOpenInAppBar path={`/feed/${encodeURIComponent(post.id)}`} />
    </main>
  );
}
