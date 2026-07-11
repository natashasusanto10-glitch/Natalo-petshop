import { prisma } from "@/lib/prisma";
import { PageHeader, AdminPage, Button } from "@/components/admin/ui";
import { LaunchPopupManagerClient } from "@/components/admin/LaunchPopupManagerClient";

export const dynamic = "force-dynamic";

export default async function AdminLaunchPopupPage() {
  const [popups, categories, brands] = await Promise.all([
    prisma.launchPopup.findMany({
      orderBy: { createdAt: "desc" },
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
        title="Popup Promo"
        subtitle={`${popups.length} popup. Muncul fullscreen saat user buka app (cold start).`}
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

      <LaunchPopupManagerClient
        initialPopups={popups.map((p) => ({
          id: p.id,
          imageUrl: p.imageUrl,
          imageAlt: p.imageAlt,
          linkType: p.linkType,
          linkValue: p.linkValue,
          audience: p.audience,
          startsAt: p.startsAt ? p.startsAt.toISOString() : null,
          endsAt: p.endsAt ? p.endsAt.toISOString() : null,
          isActive: p.isActive,
        }))}
        categories={categories}
        brands={brands}
      />
    </AdminPage>
  );
}
