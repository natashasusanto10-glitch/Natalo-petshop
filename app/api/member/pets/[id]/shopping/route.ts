import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import {
  effectivePrice,
  effectiveStock,
  type RecoProductInput,
} from "@/lib/product-dosage";
import {
  PET_SPECIES,
  rankShoppingCandidates,
  type ShoppingCandidate,
} from "@/lib/pet-shopping";

const SUGGESTED_LIMIT = 8;
const POOL_TAKE = 40;

const PRODUCT_SELECT = {
  id: true,
  slug: true,
  name: true,
  imageUrl: true,
  price: true,
  stock: true,
  targetSpecies: true,
  category: { select: { name: true } },
  variants: {
    where: { isActive: true, deletedAt: null },
    select: { price: true, stock: true },
  },
} as const;

export type ProductRow = {
  id: string;
  slug: string;
  name: string;
  imageUrl: string | null;
  price: number;
  stock: number;
  targetSpecies: string[];
  category: { name: string } | null;
  variants: { price: number; stock: number }[];
};

export type CareRecordRow = {
  productId: string | null;
  brandText: string | null;
  doneAt: Date;
};

export type UsageEntry = { usageCount: number; lastUsedAt: Date };

/**
 * Ringkas record perawatan jadi dua peta pemakaian. `records` WAJIB sudah
 * urut `doneAt` menurun supaya entri pertama yang terlihat = terbaru.
 */
export function buildUsageMaps(records: CareRecordRow[]): {
  used: Map<string, UsageEntry>;
  manual: Map<string, UsageEntry>;
} {
  const used = new Map<string, UsageEntry>();
  const manual = new Map<string, UsageEntry>();
  for (const r of records) {
    if (r.productId) {
      const prev = used.get(r.productId);
      if (prev) prev.usageCount += 1;
      else used.set(r.productId, { usageCount: 1, lastUsedAt: r.doneAt });
      continue;
    }
    const brand = (r.brandText ?? "").trim();
    if (brand === "") continue;
    const prev = manual.get(brand);
    if (prev) prev.usageCount += 1;
    else manual.set(brand, { usageCount: 1, lastUsedAt: r.doneAt });
  }
  return { used, manual };
}

function toRecoInput(row: ProductRow): RecoProductInput {
  return {
    id: row.id,
    name: row.name,
    price: row.price,
    baseStock: row.stock,
    variantStocks: row.variants.map((v) => v.stock),
    variantPrices: row.variants.map((v) => v.price),
    targetSpecies: row.targetSpecies ?? [],
    dosageRules: [],
  };
}

export function toShoppingProduct(row: ProductRow) {
  const input = toRecoInput(row);
  return {
    productId: row.id,
    slug: row.slug,
    name: row.name,
    imageUrl: row.imageUrl,
    effectivePrice: effectivePrice(input),
    // GOTCHA: produk varian punya Product.stock = 0 dan stok sebenarnya di
    // ProductVariant. effectiveStock menjumlahkan varian, jadi JANGAN pernah
    // memfilter stok di SQL — nanti semua produk varian terbuang.
    inStock: effectiveStock(input) > 0,
    hasVariants: row.variants.length > 0,
  };
}

/**
 * Gabungkan baris produk aktif dengan data pemakaian, urut terakhir-dipakai.
 * Produk yang tidak ada di `rows` (nonaktif/terhapus) otomatis hilang — dan
 * karena `usedCount` dihitung dari panjang hasil fungsi ini, angka kartu
 * statistik TIDAK MUNGKIN berbeda dari jumlah baris yang tampil.
 */
export function composeUsed(
  rows: ProductRow[],
  usage: Map<string, UsageEntry>,
) {
  return rows
    .filter((row) => usage.has(row.id))
    .map((row) => {
      const u = usage.get(row.id)!;
      return {
        ...toShoppingProduct(row),
        usageCount: u.usageCount,
        lastUsedAt: u.lastUsedAt.toISOString(),
      };
    })
    .sort((a, b) => b.lastUsedAt.localeCompare(a.lastUsedAt));
}

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const pet = await prisma.pet.findFirst({
    where: { id, userId: session.sub },
    select: { id: true, type: true },
  });
  if (!pet) {
    // 404 (bukan 403) mengikuti route care/ yang sudah ada — sekaligus tidak
    // membocorkan apakah pet milik orang lain itu ada.
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const records = (await prisma.petCareRecord.findMany({
    where: { petId: id },
    orderBy: { doneAt: "desc" },
    select: { productId: true, brandText: true, doneAt: true },
  })) as CareRecordRow[];

  const { used: usedMap, manual: manualMap } = buildUsageMaps(records);

  const usedRows = usedMap.size
    ? ((await prisma.product.findMany({
        where: { id: { in: [...usedMap.keys()] }, isActive: true },
        select: PRODUCT_SELECT,
      })) as unknown as ProductRow[])
    : [];

  const used = composeUsed(usedRows, usedMap);

  const manual = [...manualMap.entries()]
    .map(([brandText, usage]) => ({
      brandText,
      usageCount: usage.usageCount,
      lastUsedAt: usage.lastUsedAt.toISOString(),
    }))
    .sort((a, b) => b.lastUsedAt.localeCompare(a.lastUsedAt));

  // Kandidat saran: dua query berbatas, lalu diperingkat di JS supaya
  // aturannya teruji (Task 1) dan tidak perlu memindai 1300+ produk.
  const usedIds = used.map((u) => u.productId);
  const notUsed = usedIds.length ? { id: { notIn: usedIds } } : {};
  const speciesMatched = (await prisma.product.findMany({
    where: {
      isActive: true,
      ...notUsed,
      OR: [
        { targetSpecies: { has: pet.type } },
        { category: { name: { contains: pet.type, mode: "insensitive" } } },
      ],
    },
    select: PRODUCT_SELECT,
    orderBy: { createdAt: "desc" },
    take: POOL_TAKE,
  })) as unknown as ProductRow[];

  let pool = speciesMatched;
  if (pool.length < SUGGESTED_LIMIT) {
    const neutral = (await prisma.product.findMany({
      where: {
        isActive: true,
        ...notUsed,
        targetSpecies: { isEmpty: true },
        AND: PET_SPECIES.map((s) => ({
          NOT: { category: { name: { contains: s, mode: "insensitive" } } },
        })),
      },
      select: PRODUCT_SELECT,
      orderBy: { createdAt: "desc" },
      take: POOL_TAKE,
    })) as unknown as ProductRow[];
    pool = [...pool, ...neutral];
  }

  const candidates: (ShoppingCandidate & { row: ProductRow })[] = pool.map(
    (row) => ({
      id: row.id,
      targetSpecies: row.targetSpecies ?? [],
      categoryName: row.category?.name ?? null,
      row,
    }),
  );

  const suggested = rankShoppingCandidates(candidates, pet.type)
    .map((c) => toShoppingProduct(c.row))
    .filter((p) => p.inStock)
    .slice(0, SUGGESTED_LIMIT);

  return NextResponse.json({
    usedCount: used.length + manual.length,
    used,
    manual,
    suggested,
  });
}
