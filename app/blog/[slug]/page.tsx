import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getBlogPost, BLOG_POSTS } from "@/lib/blog";

export async function generateStaticParams() {
  return BLOG_POSTS.map((p) => ({ slug: p.slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const post = getBlogPost(slug);
  if (!post) return { title: "Artikel tidak ditemukan" };
  return { title: post.title, description: post.excerpt };
}

export default async function BlogDetailPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = getBlogPost(slug);
  if (!post) return notFound();

  const otherPosts = BLOG_POSTS.filter((p) => p.slug !== slug);

  // Simple markdown-like renderer for the content
  const lines = post.content.split("\n");

  return (
    <div className="mx-auto max-w-3xl px-4 py-10">
      <Link href="/blog" className="text-sm font-bold text-blue-500 hover:underline">
        ← Kembali ke Tips & Artikel
      </Link>

      <article className="mt-6">
        {/* Header */}
        <div className="flex h-32 items-center justify-center rounded-3xl bg-blue-50 text-8xl">
          {post.emoji}
        </div>

        <div className="mt-6 flex flex-wrap items-center gap-2">
          <span className="rounded-full bg-blue-100 px-3 py-1 text-xs font-semibold text-blue-500">
            {post.tag}
          </span>
          <span className="text-xs text-gray-400">{post.date}</span>
          <span className="text-xs text-gray-400">· {post.readTime} baca</span>
        </div>

        <h1 className="mt-4 text-2xl font-black leading-tight text-gray-900 lg:text-3xl">
          {post.title}
        </h1>
        <p className="mt-3 text-gray-500 leading-relaxed">{post.excerpt}</p>

        <div className="mt-8 space-y-4 text-gray-700 leading-relaxed">
          {lines.map((line, i) => {
            if (line.startsWith("## ")) {
              return <h2 key={i} className="mt-6 text-xl font-black text-gray-900">{line.slice(3)}</h2>;
            }
            if (line.startsWith("### ")) {
              return <h3 key={i} className="mt-4 text-base font-bold text-gray-900">{line.slice(4)}</h3>;
            }
            if (line.startsWith("> ")) {
              return (
                <blockquote key={i} className="border-l-4 border-blue-400 bg-blue-50 pl-4 py-3 pr-3 rounded-r-xl text-sm italic text-blue-900">
                  {line.slice(2)}
                </blockquote>
              );
            }
            if (line.startsWith("- ")) {
              return <li key={i} className="ml-5 list-disc">{line.slice(2)}</li>;
            }
            if (line.startsWith("❌ ") || line.startsWith("✅ ")) {
              return <p key={i} className="text-sm">{line}</p>;
            }
            if (line.trim() === "" || line.startsWith("|")) return null;
            return <p key={i}>{line}</p>;
          })}
        </div>
      </article>

      {/* CTA */}
      <div className="mt-10 rounded-3xl bg-blue-50 p-6 text-center">
        <p className="font-bold text-gray-900">Butuh rekomendasi produk?</p>
        <p className="mt-1 text-sm text-gray-500">Tim kami siap membantu memilih produk terbaik untuk hewan peliharaanmu.</p>
        <Link
          href="/products"
          className="mt-4 inline-flex items-center gap-2 rounded-full bg-blue-500 px-6 py-3 text-sm font-bold text-white transition hover:bg-blue-600"
        >
          Lihat Produk
        </Link>
      </div>

      {/* Other posts */}
      {otherPosts.length > 0 && (
        <section className="mt-10">
          <h2 className="font-bold text-gray-900">Artikel lainnya</h2>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            {otherPosts.slice(0, 2).map((p) => (
              <Link
                key={p.slug}
                href={`/blog/${p.slug}`}
                className="group flex gap-4 rounded-2xl border border-gray-100 bg-white p-4 transition hover:shadow-sm"
              >
                <span className="text-3xl">{p.emoji}</span>
                <div>
                  <span className="text-xs font-semibold text-blue-500">{p.tag}</span>
                  <p className="mt-1 text-sm font-bold text-gray-900 group-hover:text-blue-500 line-clamp-2">
                    {p.title}
                  </p>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
