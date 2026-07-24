import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  parseDosageRules,
  sortRecommendedProducts,
  pickDosageForWeight,
  effectivePrice,
  effectiveStock,
  type RecoProductInput,
} from "@/lib/product-dosage";

type ProductRow = {
  id: string;
  name: string;
  imageUrl: string | null;
  price: number;
  stock: number;
  dosageRules: unknown;
  targetSpecies: string[];
  variants: { price: number; stock: number }[];
};

function toRecoInput(row: ProductRow): RecoProductInput {
  return {
    id: row.id,
    name: row.name,
    price: row.price,
    baseStock: row.stock,
    variantStocks: row.variants.map((v) => v.stock),
    variantPrices: row.variants.map((v) => v.price),
    targetSpecies: row.targetSpecies ?? [],
    dosageRules: parseDosageRules(row.dosageRules),
  };
}

export function mapProductToReco(row: ProductRow, weightKg: number | null) {
  const input = toRecoInput(row);
  const dose = weightKg !== null ? pickDosageForWeight(input.dosageRules, weightKg) : null;
  return {
    id: row.id,
    name: row.name,
    imageUrl: row.imageUrl,
    effectivePrice: effectivePrice(input),
    inStock: effectiveStock(input) > 0,
    instruction: dose ? dose.instruction : null,
  };
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const category = url.searchParams.get("category");
  const species = url.searchParams.get("species") ?? "";
  const weightRaw = url.searchParams.get("weightKg");
  const weightKg = weightRaw ? Number(weightRaw) : null;

  if (category !== "deworm" && category !== "flea") {
    return NextResponse.json({ products: [] });
  }

  const rows = (await prisma.product.findMany({
    where: { careCategory: category, isActive: true },
    select: {
      id: true,
      name: true,
      imageUrl: true,
      price: true,
      stock: true,
      dosageRules: true,
      targetSpecies: true,
      variants: { where: { isActive: true, deletedAt: null }, select: { price: true, stock: true } },
    },
  })) as unknown as ProductRow[];

  let products;
  if (weightKg !== null && !Number.isNaN(weightKg)) {
    const ordered = sortRecommendedProducts(rows.map(toRecoInput), species, weightKg);
    const byId = new Map(rows.map((r) => [r.id, r]));
    products = ordered.map((o) => mapProductToReco(byId.get(o.id)!, weightKg));
  } else {
    products = rows.map((r) => mapProductToReco(r, null));
  }

  return NextResponse.json({ products });
}
