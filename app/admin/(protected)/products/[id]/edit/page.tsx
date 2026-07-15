import { notFound } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { ProductForm } from "@/components/admin/ProductForm";

export default async function AdminProductEditPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [product, categories, brands] = await Promise.all([
    prisma.product.findUnique({ where: { id }, include: { variantAttrs: { orderBy: { position: "asc" }, include: { options: { orderBy: { position: "asc" } } } }, variants: { where: { deletedAt: null }, include: { options: { select: { optionId: true } } }, orderBy: { createdAt: "asc" } } } }),
    prisma.category.findMany({ orderBy: { name: "asc" }, select: { id: true, name: true } }),
    prisma.brand.findMany({ orderBy: { name: "asc" }, select: { id: true, name: true } }),
  ]);
  if (!product) return notFound();
  return <ProductForm mode="edit" categories={categories} brands={brands} initialProduct={product} />;
}
