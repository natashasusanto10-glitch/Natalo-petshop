/**
 * /admin/stock — pemantauan stok (MONITORING-only).
 *
 * Mutasi (edit / arsip / hapus) dipusatkan di /admin/products supaya tidak
 * duplikat di dua tempat; tiap baris di sini hanya menautkan ke sana.
 *
 * DUA PERBAIKAN:
 *
 * 1. Halaman ini dulu menarik SELURUH produk aktif (1.400+) ke memori lalu
 *    menyaring di JavaScript. Sekarang dipaginasi dan angkanya dari query
 *    hitung, jadi kartu statistik tetap mencakup seluruh katalog.
 *
 * 2. Stok produk hanya bisa menjawab "produk ini menipis", tidak "varian yang
 *    MANA". Tab varian menutup itu: 143 varian menipis tidak terlihat sama
 *    sekali di versi lama karena tenggelam dalam jumlah stok induknya.
 *    (`Product.stock` sendiri adalah agregat terpelihara dari stok varian —
 *    lihat catatan di lib/admin/stock-filters.ts.)
 */
import { prisma } from "@/lib/prisma";
import { StockView } from "@/components/admin/views/StockView";
import { parsePageParam } from "@/lib/admin/pagination";
import {
  parseStockFilter,
  parseStockTab,
  productStockWhere,
  variantStockWhere,
  type StockFilter,
  type StockTab,
} from "@/lib/admin/stock-filters";

// Selalu render fresh — stok sering berubah dan admin mengharapkan angkanya
// akurat, jadi halaman ini tidak boleh kena full-route cache Next.js.
export const dynamic = "force-dynamic";

const PAGE_SIZE = 25;

export default async function AdminStockPage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string; filter?: string; page?: string }>;
}) {
  const sp = await searchParams;
  const tab = parseStockTab(sp.tab);
  const filter = parseStockFilter(sp.filter);
  const page = parsePageParam(sp.page);

  const productWhere = productStockWhere(filter);
  const varianWhere = variantStockWhere(filter);
  const skip = (page - 1) * PAGE_SIZE;

  const [
    productTotal,
    productLow,
    productOut,
    variantLow,
    variantOut,
    listedTotal,
    products,
    variants,
  ] = await Promise.all([
    prisma.product.count({ where: productStockWhere("semua") }),
    prisma.product.count({ where: productStockWhere("menipis") }),
    prisma.product.count({ where: productStockWhere("habis") }),
    prisma.productVariant.count({ where: variantStockWhere("menipis") }),
    prisma.productVariant.count({ where: variantStockWhere("habis") }),
    tab === "produk"
      ? prisma.product.count({ where: productWhere })
      : prisma.productVariant.count({ where: varianWhere }),
    tab === "produk"
      ? prisma.product.findMany({
          where: productWhere,
          orderBy: [{ stock: "asc" }, { name: "asc" }],
          skip,
          take: PAGE_SIZE,
          select: {
            id: true,
            name: true,
            stock: true,
            category: { select: { name: true } },
          },
        })
      : Promise.resolve([]),
    tab === "varian"
      ? prisma.productVariant.findMany({
          where: varianWhere,
          orderBy: [{ stock: "asc" }, { sku: "asc" }],
          skip,
          take: PAGE_SIZE,
          select: {
            id: true,
            sku: true,
            stock: true,
            product: { select: { id: true, name: true } },
            options: { select: { option: { select: { value: true } } } },
          },
        })
      : Promise.resolve([]),
  ]);

  const totalPages = Math.ceil(listedTotal / PAGE_SIZE);
  const pageBeyondEnd = listedTotal > 0 && page > totalPages;

  const buildUrl = (overrides: {
    tab?: StockTab;
    filter?: StockFilter;
    page?: number;
  }) => {
    const next = new URLSearchParams();
    const t = overrides.tab ?? tab;
    const f = overrides.filter ?? filter;
    // Ganti tab atau filter selalu kembali ke halaman 1 — nomor halaman lama
    // tidak berarti apa-apa di kumpulan baris yang berbeda.
    const p = overrides.page ?? 1;
    if (t !== "produk") next.set("tab", t);
    if (f !== "semua") next.set("filter", f);
    if (p > 1) next.set("page", String(p));
    const str = next.toString();
    return `/admin/stock${str ? `?${str}` : ""}`;
  };

  const isEmpty =
    tab === "produk" ? products.length === 0 : variants.length === 0;

  return (
    <StockView
      {...{
        productTotal,
        productLow,
        productOut,
        variantLow,
        variantOut,
        listedTotal,
        tab,
        filter,
        page,
        totalPages,
        pageBeyondEnd,
        isEmpty,
        products,
        variants,
        buildUrl,
      }}
    />
  );
}
