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
import Link from "next/link";
import { prisma } from "@/lib/prisma";
import {
  PageHeader,
  StatCard,
  EmptyState,
  Badge,
  AdminPage,
  Button,
  Pagination,
} from "@/components/admin/ui";
import { parsePageParam } from "@/lib/admin/pagination";
import {
  LOW_STOCK_LIMIT,
  parseStockFilter,
  parseStockTab,
  productStockWhere,
  stockTone,
  variantStockWhere,
  type StockFilter,
  type StockTab,
} from "@/lib/admin/stock-filters";

// Selalu render fresh — stok sering berubah dan admin mengharapkan angkanya
// akurat, jadi halaman ini tidak boleh kena full-route cache Next.js.
export const dynamic = "force-dynamic";

const PAGE_SIZE = 25;

const FILTER_TABS: Array<{ key: StockFilter; label: string }> = [
  { key: "semua", label: "Semua" },
  { key: "menipis", label: `Menipis (1-${LOW_STOCK_LIMIT})` },
  { key: "habis", label: "Habis" },
];

function variantLabel(options: Array<{ option: { value: string } }>): string {
  return options.map((o) => o.option.value).join(" / ") || "Tanpa opsi";
}

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

  const isEmpty = tab === "produk" ? products.length === 0 : variants.length === 0;

  return (
    <AdminPage maxWidth="lg">
      <PageHeader
        title="📦 Stok"
        subtitle="Pantau stok produk & varian. Kelola (edit / arsip / hapus) di halaman Produk."
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

      <section className="mt-6 grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-5">
        <StatCard
          label="Produk Aktif"
          value={productTotal}
          helper="Tampil di toko"
          variant="default"
        />
        <StatCard
          label="Produk Menipis"
          value={productLow}
          helper={`Stok 1-${LOW_STOCK_LIMIT}`}
          href={buildUrl({ tab: "produk", filter: "menipis" })}
          variant="warning"
        />
        <StatCard
          label="Produk Habis"
          value={productOut}
          helper="Stok 0"
          href={buildUrl({ tab: "produk", filter: "habis" })}
          variant="danger"
        />
        <StatCard
          label="Varian Menipis"
          value={variantLow}
          helper={`Stok 1-${LOW_STOCK_LIMIT}`}
          href={buildUrl({ tab: "varian", filter: "menipis" })}
          variant="warning"
        />
        <StatCard
          label="Varian Habis"
          value={variantOut}
          helper="Stok 0"
          href={buildUrl({ tab: "varian", filter: "habis" })}
          variant="danger"
        />
      </section>

      {/* Tab produk vs varian. Daftar produk memakai stok total; daftar varian
          memecahnya per kombinasi, supaya terlihat varian MANA yang menipis —
          pertanyaan yang tidak bisa dijawab angka total. */}
      <div className="mt-6 flex flex-wrap gap-2">
        {(["produk", "varian"] as const).map((key) => (
          <Link
            key={key}
            href={buildUrl({ tab: key })}
            className={`rounded-full px-4 py-2 text-sm font-bold transition ${
              tab === key
                ? "bg-natalo-600 text-white shadow-[0_4px_12px_-2px_rgba(30,95,191,0.4)]"
                : "border border-zinc-200 bg-white text-zinc-600 hover:border-zinc-400"
            }`}
          >
            {key === "produk" ? "Produk (stok total)" : "Varian produk"}
          </Link>
        ))}
      </div>

      <div className="mt-3 flex flex-wrap gap-1.5">
        {FILTER_TABS.map((f) => (
          <Link
            key={f.key}
            href={buildUrl({ filter: f.key })}
            className={`rounded-full px-3 py-1 text-xs font-bold transition ${
              filter === f.key
                ? "bg-natalo-50 text-natalo-700"
                : "text-zinc-500 hover:bg-zinc-50 hover:text-zinc-700"
            }`}
          >
            {f.label}
          </Link>
        ))}
      </div>

      <p className="mt-3 text-xs font-semibold text-zinc-500">
        {listedTotal} baris{filter !== "semua" ? " pada filter ini" : ""}
      </p>

      {pageBeyondEnd ? (
        <div className="mt-3 rounded-2xl border border-zinc-200 bg-white">
          <EmptyState
            icon="📄"
            title={`Halaman ${page} tidak ada`}
            description={`Daftar ini hanya sampai halaman ${totalPages}.`}
            action={{ label: "Kembali ke halaman 1", href: buildUrl({ page: 1 }) }}
            size="full"
          />
        </div>
      ) : isEmpty ? (
        <div className="mt-3 rounded-2xl border border-zinc-200 bg-white">
          <EmptyState
            icon={filter === "semua" ? "📭" : "✅"}
            title={
              filter === "habis"
                ? "Tidak ada yang habis — aman"
                : filter === "menipis"
                  ? "Tidak ada yang menipis — aman"
                  : tab === "varian"
                    ? "Belum ada varian"
                    : "Belum ada produk"
            }
            description={
              filter === "semua"
                ? "Tambahkan produk untuk mulai memantau stok."
                : "Coba filter lain untuk melihat sisa daftarnya."
            }
            size="full"
          />
        </div>
      ) : tab === "produk" ? (
        <StockTable
          rows={products.map((p) => ({
            key: p.id,
            productId: p.id,
            title: p.name,
            subtitle: p.category?.name ?? "Tanpa kategori",
            stock: p.stock,
          }))}
        />
      ) : (
        <StockTable
          rows={variants.map((v) => ({
            key: v.id,
            productId: v.product.id,
            title: v.product.name,
            subtitle: `${variantLabel(v.options)}${v.sku ? ` · ${v.sku}` : ""}`,
            stock: v.stock,
          }))}
        />
      )}

      {!pageBeyondEnd && (
        <Pagination
          currentPage={page}
          totalPages={totalPages}
          hrefFor={(target) => buildUrl({ page: target })}
          summary={`${listedTotal} baris`}
        />
      )}
    </AdminPage>
  );
}

type StockRow = {
  key: string;
  productId: string;
  title: string;
  subtitle: string;
  stock: number;
};

/** Satu tabel dipakai tab produk maupun varian — bedanya hanya isi subtitle. */
function StockTable({ rows }: { rows: StockRow[] }) {
  return (
    <>
      {/* Kartu untuk layar sempit */}
      <div className="mt-3 space-y-3 md:hidden">
        {rows.map((row) => {
          const tone = stockTone(row.stock);
          return (
            <div
              key={row.key}
              className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <p className="line-clamp-2 font-semibold text-zinc-950">{row.title}</p>
                  <p className="mt-0.5 truncate text-xs text-zinc-500">{row.subtitle}</p>
                </div>
                <div className="shrink-0 text-right">
                  <p
                    className={`text-2xl font-black ${
                      tone.badge === "danger"
                        ? "text-red-600"
                        : tone.badge === "warning"
                          ? "text-amber-600"
                          : "text-zinc-900"
                    }`}
                  >
                    {row.stock}
                  </p>
                  <div className="mt-1">
                    <Badge variant={tone.badge}>{tone.label}</Badge>
                  </div>
                </div>
              </div>
              <div className="mt-3 border-t border-zinc-100 pt-3">
                <Button
                  href={`/admin/products/${row.productId}/edit`}
                  variant="secondary"
                  size="sm"
                  fullWidth
                >
                  Kelola di Produk →
                </Button>
              </div>
            </div>
          );
        })}
      </div>

      {/* Tabel untuk layar lebar */}
      <div className="mt-3 hidden overflow-hidden rounded-2xl border border-zinc-200 bg-white md:block">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-100 bg-zinc-50/50">
                <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                  Produk
                </th>
                <th className="hidden px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500 lg:table-cell">
                  Kategori / Varian
                </th>
                <th className="px-5 py-3.5 text-right text-[11px] font-black uppercase tracking-wider text-zinc-500">
                  Stok
                </th>
                <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                  Status
                </th>
                <th className="px-5 py-3.5 text-right text-[11px] font-black uppercase tracking-wider text-zinc-500">
                  Aksi
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => {
                const tone = stockTone(row.stock);
                return (
                  <tr
                    key={row.key}
                    className="border-b border-zinc-100 transition last:border-0 hover:bg-natalo-50/40"
                  >
                    <td className="px-5 py-4">
                      <p className="font-semibold text-zinc-900">{row.title}</p>
                    </td>
                    <td className="hidden px-5 py-4 text-zinc-500 lg:table-cell">
                      {row.subtitle}
                    </td>
                    <td className="px-5 py-4 text-right">
                      <span
                        className={`font-bold ${
                          tone.badge === "danger"
                            ? "text-red-600"
                            : tone.badge === "warning"
                              ? "text-amber-600"
                              : "text-zinc-900"
                        }`}
                      >
                        {row.stock}
                      </span>
                    </td>
                    <td className="px-5 py-4">
                      <Badge variant={tone.badge} size="md">
                        {tone.label}
                      </Badge>
                    </td>
                    <td className="px-5 py-4">
                      <div className="flex items-center justify-end">
                        <Button
                          href={`/admin/products/${row.productId}/edit`}
                          variant="secondary"
                          size="sm"
                        >
                          Kelola →
                        </Button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
