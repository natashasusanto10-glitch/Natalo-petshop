import type { Metadata } from "next";
import Link from "next/link";
import { BLOG_POSTS } from "@/lib/blog";

export const metadata: Metadata = {
  title: "Tips & Artikel",
  description: "Tips perawatan hewan peliharaan, panduan pakan, dan artikel informatif dari Natalo Petshop.",
};

export default function BlogPage() {
  return (
    <div className="mx-auto max-w-4xl px-4 py-10">
      <div>
        <h1 className="text-3xl font-black text-gray-900">Tips & Artikel</h1>
        <p className="mt-1 text-sm text-gray-500">Info perawatan hewan peliharaan untuk kamu</p>
      </div>

      <div className="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        {BLOG_POSTS.map((post) => (
          <Link
            key={post.slug}
            href={`/blog/${post.slug}`}
            className="group overflow-hidden rounded-2xl bg-white shadow-sm border border-gray-100 transition hover:shadow-md"
          >
            <div className="flex h-44 items-center justify-center bg-orange-50 text-7xl">
              {post.emoji}
            </div>
            <div className="p-5">
              <div className="flex items-center gap-2">
                <span className="rounded-full bg-orange-100 px-3 py-1 text-xs font-semibold text-orange-500">
                  {post.tag}
                </span>
                <span className="text-xs text-gray-400">{post.readTime}</span>
              </div>
              <h2 className="mt-3 font-bold leading-snug text-gray-900 group-hover:text-orange-500 line-clamp-2">
                {post.title}
              </h2>
              <p className="mt-2 text-xs text-gray-500 line-clamp-2">{post.excerpt}</p>
              <p className="mt-3 text-xs text-gray-400">{post.date}</p>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
