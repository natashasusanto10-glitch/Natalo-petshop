/**
 * /admin/diskon/promo-toko/[id]/edit — Edit Promo Toko
 *
 * Server wrapper: fetch existing discount, hydrate ke PromoTokoForm
 * dengan initial data + excludeId (supaya eligible-products query
 * tetap include produk yang sudah di promo ini).
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
  });
  if (!discount) return notFound();

  return (
    <PromoTokoForm
      excludeId={id}
      initial={{
        id: discount.id,
        name: discount.name,
        discountType: discount.discountType,
        discountValue: String(discount.discountValue),
        maxDiscountCap: discount.maxDiscountCap
          ? String(discount.maxDiscountCap)
          : "",
        startsAt: toDateTimeLocal(discount.startsAt),
        endsAt: toDateTimeLocal(discount.endsAt),
        productIds: discount.productIds,
        isActive: discount.isActive,
      }}
    />
  );
}
