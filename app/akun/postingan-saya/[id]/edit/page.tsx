import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { requireCustomerSession } from "@/lib/session-guards";
import { MY_FEED_VISIBLE_STATUSES } from "@/lib/feed/my-posts";
import { EditMyFeedPostClient } from "@/components/feed/EditMyFeedPostClient";

export const metadata: Metadata = {
  title: "Edit Postingan",
  robots: { index: false, follow: false },
};

type PageProps = {
  params: Promise<{ id: string }>;
};

function extractPetType(description: string | null): string | null {
  if (!description) return null;
  const m = description.match(/Info peliharaan:\s*(cat|dog|other|kucing|anjing|lainnya)/i);
  if (!m) return null;
  const v = m[1].toLowerCase();
  if (v === "cat" || v === "kucing") return "cat";
  if (v === "dog" || v === "anjing") return "dog";
  return "other";
}

function extractCaption(description: string | null, title: string): string {
  if (!description) return title === "Postingan baru" ? "" : title;
  // Strip "Info peliharaan: ..." line dari description.
  const cleaned = description
    .split(/\n+/)
    .map((line) => line.trim())
    .filter((line) => line && !/^info peliharaan\s*:/i.test(line))
    .join("\n")
    .trim();
  return cleaned;
}

export default async function EditMyFeedPostPage({ params }: PageProps) {
  const session = await requireCustomerSession();
  if (!session) {
    redirect("/member/login?returnUrl=/akun/postingan-saya");
  }

  const { id: postId } = await params;

  const post = await prisma.feedPost.findFirst({
    where: {
      id: postId,
      authorId: session.sub,
      authorRole: "CUSTOMER",
      kind: "COMMUNITY",
      deletedAt: null,
      status: { in: [...MY_FEED_VISIBLE_STATUSES] },
    },
    include: {
      taggedProducts: {
        select: {
          position: true,
          product: {
            select: {
              id: true,
              slug: true,
              name: true,
              price: true,
              imageUrl: true,
            },
          },
        },
        orderBy: { position: "asc" },
      },
    },
  });

  if (!post) notFound();

  const caption = extractCaption(post.description, post.title);
  const petType = extractPetType(post.description);

  const initialProducts = post.taggedProducts
    .filter((tp) => tp.product)
    .map((tp) => ({
      productId: tp.product!.id,
      slug: tp.product!.slug,
      name: tp.product!.name,
      price: tp.product!.price,
      imageUrl: tp.product!.imageUrl,
    }));

  return (
    <main className="mx-auto max-w-2xl px-4 py-6">
      <EditMyFeedPostClient
        postId={post.id}
        initialCaption={caption}
        initialPetType={petType as "cat" | "dog" | "other" | null}
        initialProducts={initialProducts}
        thumbnailUrl={post.thumbnailUrl}
        videoDurationSec={post.videoDurationSec}
        status={post.status}
      />
    </main>
  );
}
