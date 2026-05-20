/**
 * /admin/diskon/promo-toko/[id]/edit — Edit Promo Toko
 *
 * Server wrapper: fetch existing discount + items (with product/variant
 * details), hydrate ke PromoTokoForm dengan initial data + excludeId.
 */
import { notFound } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { PromoTokoForm } from "@/components/admin/PromoTokoForm";

export const dynamic = "force-dynamic";

function toDateTimeLocal(d: Date): string {
  // HTML datetime-local format: YYYY-MM-DDTHH:MM (local time, no TZ)
  const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
}

export default async function PromoTokoEditPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const discount = await prisma.productDiscount.findUnique({
    where: { id },
    include: {
      items: {
        include: {
          product: {
            select: {
              id: true,
              name: true,
              imageUrl: true,
              price: true,
              stock: true,
              hasVariants: true,
            },
          },
          variant: {
            select: {
              id: true,
              sku: true,
              price: true,
              stock: true,
              imageUrl: true,
              options: {
                select: { option: { select: { value: true } } },
              },
            },
          },
        },
      },
    },
  });
  if (!discount) return notFound();

  // Transform items ke struktur yang PromoTokoForm consume.
  const initialItems = discount.items.map((it) => ({
    productId: it.productId,
    variantId: it.variantId,
    discountedPrice: it.discountedPrice,
    isItemActive: it.isItemActive,
    product: it.product,
    variant: it.variant
      ? {
          ...it.variant,
          label:
            it.variant.options.map((o) => o.option.value).join(" / ") ||
            it.variant.sku ||
            "Default",
        }
      : null,
  }));

  return (
    <PromoTokoForm
      excludeId={id}
      initial={{
        id: discount.id,
        name: discount.name,
        startsAt: toDateTimeLocal(discount.startsAt),
        endsAt: toDateTimeLocal(discount.endsAt),
        items: initialItems,
        isActive: discount.isActive,
      }}
    />
  );
}
