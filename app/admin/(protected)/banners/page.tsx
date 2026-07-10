import { prisma } from "@/lib/prisma";
import { PageHeader, AdminPage, Button } from "@/components/admin/ui";
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
    <AdminPage maxWidth="lg">
      <PageHeader
        title="Banner Beranda"
        subtitle={`${banners.length} banner. Slider di halaman Beranda app customer.`}
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
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
    </AdminPage>
  );
}
