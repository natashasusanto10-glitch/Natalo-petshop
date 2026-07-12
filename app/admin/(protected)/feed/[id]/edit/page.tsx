import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { bunnyThumbnailUrl, signBunnyUrl } from "@/lib/feed/bunny";
import { AdminEditFeedPostClient } from "@/components/admin/feed/AdminEditFeedPostClient";
import { AdminPage } from "@/components/admin/ui";

export const metadata: Metadata = {
  title: "Edit Postingan — Admin",
};

type PageProps = {
  params: Promise<{ id: string }>;
};

export default async function AdminEditFeedPostPage({ params }: PageProps) {
  const session = await requireAdminSession();
  if (!session) {
    redirect("/admin/login");
  }

  const { id: postId } = await params;

  const post = await prisma.feedPost.findFirst({
    where: {
      id: postId,
      authorId: session.sub,
      authorRole: "ADMIN",
      deletedAt: null,
    },
    include: {
      taggedProducts: {
        select: {
          position: true,
          promoPrice: true,
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

  const initialProducts = post.taggedProducts
    .filter((tp) => tp.product)
    .map((tp) => ({
      productId: tp.product!.id,
      slug: tp.product!.slug,
      name: tp.product!.name,
      price: tp.product!.price,
      imageUrl: tp.product!.imageUrl,
      promoPrice: tp.promoPrice,
    }));

  return (
    <AdminPage maxWidth="lg">
      <AdminEditFeedPostClient
        postId={post.id}
        initialTitle={post.title}
        initialDescription={post.description ?? ""}
        initialProducts={initialProducts}
        thumbnailUrl={
          signBunnyUrl(
            post.thumbnailUrl ??
              (post.videoGuid ? bunnyThumbnailUrl(post.videoGuid) : null),
          ) ?? null
        }
        videoDurationSec={post.videoDurationSec}
        kind={post.kind}
        tab={post.tab}
      />
    </AdminPage>
  );
}
