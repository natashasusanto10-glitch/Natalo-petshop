import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import {
  effectivePrice,
  effectiveStock,
  type RecoProductInput,
} from "@/lib/product-dosage";
import {
  allowedCategoriesFor,
  selectSuggestionIds,
  type ShoppingCandidate,
} from "@/lib/pet-shopping";

/** Slot grid halaman penuh; rail profil memakai 6 pertama dari urutan sama. */
export const SUGGESTED_LIMIT = 12;

/**
 * Kolom minimal untuk menghitung stok efektif + grup kategori. Query ringan
 * ini boleh menyapu seluruh kandidat spesies (≤380 baris di katalog per
 * 2026-07-26) karena payload per baris sangat kecil; baris PENUH hanya
 * diambil untuk 12 id yang benar-benar terpilih.
 */
const STOCK_SELECT = {
  id: true,
  stock: true,
  targetSpecies: true,
  category: { select: { name: true } },
  variants: {
    where: { isActive: true, deletedAt: null },
    select: { stock: true },
  },
} as const;

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

export type StockRow = {
  id: string;
  stock: number;
  targetSpecies: string[];
  category: { name: string } | null;
  variants: { stock: number }[];
};

/** Kandidat + status stok efektif (base + semua varian aktif). */
export function toStockCandidate(
  row: StockRow,
): ShoppingCandidate & { inStock: boolean } {
  return {
    id: row.id,
    targetSpecies: row.targetSpecies ?? [],
    categoryName: row.category?.name ?? null,
    // GOTCHA: produk varian punya Product.stock = 0 dan stok sebenarnya di
    // ProductVariant, jadi stok TIDAK BOLEH difilter di SQL. WAJIB pakai
    // effectiveStock yang sama dengan toShoppingProduct di bawah — kalau
    // dua fungsi ini punya semantik stok yang beda, kandidat bisa lolos
    // seleksi di sini tapi dilaporkan habis di respons akhir (kartu saran
    // tanpa indikator stok, produk ternyata tak bisa dibeli).
    inStock:
      effectiveStock({
        id: row.id,
        name: "",
        price: 0,
        baseStock: row.stock,
        variantStocks: row.variants.map((v) => v.stock),
        variantPrices: [],
        targetSpecies: [],
        dosageRules: [],
      }) > 0,
  };
}

/**
 * Buang produk habis SEBELUM seleksi. Urutannya penting: kalau filter stok
 * terjadi setelah `selectSuggestionIds`, permintaan 12 slot bisa berakhir
 * jadi 7 kartu karena sebagian tersaring — slot bocor tanpa sebab terlihat.
 */
export function inStockCandidates(rows: StockRow[]): ShoppingCandidate[] {
  return rows
    .map(toStockCandidate)
    .filter((c) => c.inStock)
    .map(({ id, targetSpecies, categoryName }) => ({
      id,
      targetSpecies,
      categoryName,
    }));
}

/** Susun baris penuh mengikuti urutan `ids` (urutan DB tidak dijamin). */
export function orderRowsByIds(
  rows: ProductRow[],
  ids: string[],
): ProductRow[] {
  const byId = new Map(rows.map((r) => [r.id, r]));
  return ids
    .map((id) => byId.get(id))
    .filter((r): r is ProductRow => r !== undefined);
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

  // Kandidat saran: satu query RINGAN untuk seluruh kategori allowlist,
  // seleksi murni (allowlist + rotasi harian + penjalinan) di JS, lalu satu
  // query PENUH untuk 12 id terpilih. Pola ini menggantikan pool
  // "40 produk terbaru" yang lama — pool itu membuat 200+ produk lain tak
  // pernah punya kesempatan tampil, jadi rotasi apa pun tak akan terasa.
  const usedIds = used.map((u) => u.productId);
  const notUsed = usedIds.length ? { id: { notIn: usedIds } } : {};
  const allowedCategories = [...allowedCategoriesFor(pet.type)];

  const stockRows =
    allowedCategories.length === 0
      ? ((await prisma.product.findMany({
          where: {
            isActive: true,
            ...notUsed,
            targetSpecies: { has: pet.type },
          },
          select: STOCK_SELECT,
          orderBy: [{ createdAt: "desc" }, { id: "asc" }],
        })) as unknown as StockRow[])
      : ((await prisma.product.findMany({
          where: {
            isActive: true,
            ...notUsed,
            OR: [
              { targetSpecies: { has: pet.type } },
              { category: { name: { in: allowedCategories } } },
            ],
          },
          select: STOCK_SELECT,
          // Urutan dasar deterministik — id sebagai tie-break supaya rotasi
          // harian tidak bergeser hanya karena dua produk lahir bersamaan.
          orderBy: [{ createdAt: "desc" }, { id: "asc" }],
        })) as unknown as StockRow[]);

  const suggestedIds = selectSuggestionIds(inStockCandidates(stockRows), {
    petType: pet.type,
    petId: pet.id,
    now: new Date(),
    limit: SUGGESTED_LIMIT,
  });

  const suggestedRows = suggestedIds.length
    ? ((await prisma.product.findMany({
        where: { id: { in: suggestedIds } },
        select: PRODUCT_SELECT,
      })) as unknown as ProductRow[])
    : [];

  const suggested = orderRowsByIds(suggestedRows, suggestedIds).map(
    toShoppingProduct,
  );

  return NextResponse.json({
    usedCount: used.length + manual.length,
    used,
    manual,
    suggested,
  });
}
