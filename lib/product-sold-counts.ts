import { prisma } from "@/lib/prisma";
import { VALID_SALES_ORDER_STATUSES } from "@/lib/product-ranking";

/** Fetch quantities in one batch for both product listings and search results. */
export async function attachProductSoldCounts<T extends { id: string }>(
  products: T[]
): Promise<Array<T & { soldCount: number }>> {
  if (products.length === 0) return [];
  const rows = await prisma.orderItem.groupBy({
    by: ["productId"],
    where: {
      productId: { in: products.map(product => product.id) },
      order: {
        paymentStatus: "PAID",
        status: { in: VALID_SALES_ORDER_STATUSES },
      },
    },
    _sum: { quantity: true },
  });
  const counts = new Map(rows.map(row => [row.productId, row._sum.quantity ?? 0]));
  return products.map(product => ({ ...product, soldCount: counts.get(product.id) ?? 0 }));
}
