import Link from "next/link";
import {
  PageHeader,
  StatCard,
  EmptyState,
  Badge,
  AdminPage,
  Button,
  Pagination,
} from "@/components/admin/ui";
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

const FILTER_TABS: Array<{ key: StockFilter; label: string }> = [
  { key: "semua", label: "Semua" },
  { key: "menipis", label: `Menipis (1-${LOW_STOCK_LIMIT})` },
  { key: "habis", label: "Habis" },
];

function variantLabel(options: Array<{ option: { value: string } }>): string {
  return options.map((o) => o.option.value).join(" / ") || "Tanpa opsi";
}

export type StockViewProps = {
  search?: string;
  productTotal: number;
  productLow: number;
  productOut: number;
  variantLow: number;
  variantOut: number;
  listedTotal: number;
  tab: StockTab;
  filter: StockFilter;
  page: number;
  totalPages: number;
  pageBeyondEnd: boolean;
  isEmpty: boolean;
  products: Array<{
    id: string;
    name: string;
    stock: number;
    category: { name: string } | null;
  }>;
  variants: Array<{
    id: string;
    sku: string | null;
    stock: number;
    product: { id: string; name: string };
    options: Array<{ option: { value: string } }>;
  }>;
  buildUrl: (overrides: {
    tab?: StockTab;
    filter?: StockFilter;
    page?: number;
    q?: string;
  }) => string;
};
export function StockView({
  search = "",
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
}: StockViewProps) {
  return (
    <AdminPage
      maxWidth="lg"
      className="admin-operational-page admin-refined-page admin-stock-page"
    >
      <PageHeader
        eyebrow="Inventori"
        title="Pantau stok"
        subtitle="Temukan produk dan varian yang perlu diisi kembali."
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            Kembali ke ringkasan
          </Button>
        }
      />

      <section className="admin-stock-stats mt-6 grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-5">
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

      <section className="admin-list-workspace" aria-label="Daftar stok">
        <form method="get" action="/admin/stock" className="mb-4 flex flex-wrap items-end gap-2">
          <input type="hidden" name="tab" value={tab} /><input type="hidden" name="filter" value={filter} />
          <label className="flex-1 min-w-48 text-sm font-medium">Cari produk atau SKU<input type="search" name="q" defaultValue={search} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2" /></label>
          <Button type="submit" size="sm">Cari</Button>{search && <Button href={buildUrl({ q: "" })} variant="secondary" size="sm">Atur ulang</Button>}
        </form>
        {/* Tab produk vs varian. Daftar produk memakai stok total; daftar varian
          memecahnya per kombinasi, supaya terlihat varian MANA yang menipis —
          pertanyaan yang tidak bisa dijawab angka total. */}
        <div className="admin-filter-tabs" aria-label="Jenis stok">
          {(["produk", "varian"] as const).map((key) => (
            <Link
              key={key}
              href={buildUrl({ tab: key })}
              aria-current={tab === key ? "page" : undefined}
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

        <div className="admin-filter-secondary" aria-label="Filter stok">
          {FILTER_TABS.map((f) => (
            <Link
              key={f.key}
              href={buildUrl({ filter: f.key })}
              aria-current={filter === f.key ? "page" : undefined}
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
              action={{
                label: "Kembali ke halaman 1",
                href: buildUrl({ page: 1 }),
              }}
              size="full"
            />
          </div>
        ) : isEmpty ? (
          <div className="mt-3 rounded-2xl border border-zinc-200 bg-white">
            <EmptyState
              icon={filter === "semua" ? "📭" : "✅"}
              title={
                search ? "Tidak ada hasil pencarian" : filter === "habis"
                  ? "Tidak ada yang habis — aman"
                  : filter === "menipis"
                  ? "Tidak ada yang menipis — aman"
                  : tab === "varian"
                  ? "Belum ada varian"
                  : "Belum ada produk"
              }
              description={
                search ? "Coba nama produk atau SKU lainnya." : filter === "semua"
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
              subtitle: `${variantLabel(v.options)}${
                v.sku ? ` · ${v.sku}` : ""
              }`,
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
      </section>
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
      <div className="mt-3 space-y-3 xl:hidden">
        {rows.map((row) => {
          const tone = stockTone(row.stock);
          return (
            <div
              key={row.key}
              className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <p className="line-clamp-2 font-semibold text-zinc-950">
                    {row.title}
                  </p>
                  <p className="mt-0.5 truncate text-xs text-zinc-500">
                    {row.subtitle}
                  </p>
                </div>
                <div className="shrink-0 text-right">
                  <p
                    className={`text-2xl font-semibold ${
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
                    <span className="inline-flex whitespace-nowrap"><Badge variant={tone.badge}>{tone.label}</Badge></span>
                  </div>
                </div>
              </div>
              <div className="mt-3 border-t border-zinc-100 pt-3">
                <Button
                  href={`/admin/products/${row.productId}/edit`}
                  target="_blank"
                  rel="noopener noreferrer"
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
      <div className="mt-3 hidden overflow-hidden rounded-2xl border border-zinc-200 bg-white xl:block">
        <div className="overflow-x-auto">
          <table className="admin-data-table w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-100 bg-zinc-50/50">
                <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                  Produk
                </th>
                <th className="hidden px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500 lg:table-cell">
                  Kategori / Varian
                </th>
                <th className="px-5 py-3.5 text-right text-xs font-semibold uppercase tracking-wider text-zinc-500">
                  Stok
                </th>
                <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                  Status
                </th>
                <th className="px-5 py-3.5 text-right text-xs font-semibold uppercase tracking-wider text-zinc-500">
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
                      <span className="inline-flex whitespace-nowrap"><Badge variant={tone.badge} size="md">
                        {tone.label}
                      </Badge></span>
                    </td>
                    <td className="px-5 py-4">
                      <div className="flex items-center justify-end">
                        <Button
                          href={`/admin/products/${row.productId}/edit`}
                          target="_blank"
                          rel="noopener noreferrer"
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
