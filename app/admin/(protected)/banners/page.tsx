import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { PageHeader } from "@/components/admin/ui";
import { BannerManagerClient } from "@/components/admin/BannerManagerClient";

export const dynamic = "force-dynamic";

export default async function AdminBannersPage() {
  const [banners, categories, brands] = await Promise.all([
    prisma.homeBanner.findMany({
      orderBy: [{ position: "asc" }, { createdAt: "desc" }],
    }),
    prisma.category.findMany({
      orderBy: { name: "asc" },
      select: { slug: true, name: true },
    }),
    prisma.brand.findMany({
      where: { isActive: true },
      orderBy: { name: "asc" },
      select: { slug: true, name: true },
    }),
  ]);

  return (
    <div className="mx-auto max-w-3xl px-4 py-5 md:py-10">
      <PageHeader
        title="Banner Beranda"
        subtitle={`${banners.length} banner. Slider di halaman Beranda app customer.`}
        actions={
          <Link
            href="/admin/dashboard"
            className="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-3.5 py-2 text-xs font-bold text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-50"
          >
            ← Dashboard
          </Link>
        }
      />

      <BannerManagerClient
        initialBanners={banners.map((b) => ({
          id: b.id,
          imageUrl: b.imageUrl,
          imageAlt: b.imageAlt,
          linkType: b.linkType,
          linkValue: b.linkValue,
          isActive: b.isActive,
          position: b.position,
        }))}
        categories={categories}
        brands={brands}
      />
    </div>
  );
}
