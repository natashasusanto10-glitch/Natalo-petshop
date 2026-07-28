import Image from "next/image";
import Link from "next/link";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { deleteProductVideo } from "@/lib/product/product-video";
import { productIsVisibleWhere } from "@/lib/product/admin-product-form";
import { productSearchWhere } from "@/lib/search";
import { formatRupiah } from "@/lib/format";
import { InlineEditCell } from "@/components/admin/InlineEditCell";
import { VariantInlineEditCell } from "@/components/admin/VariantInlineEditCell";
import { ConfirmSubmitButton } from "@/components/ConfirmSubmitButton";
import { PageHeader, EmptyState, AdminPage, Button } from "@/components/admin/ui";
import {
  ProductSelectionProvider,
  ProductSelectAll,
  ProductRowCheckbox,
  ProductBulkBar,
} from "@/components/admin/ProductBulkSelect";

const PAGE_SIZE = 50;

// Produk yang diedit/dibuat admin dalam jendela ini dapat badge "Baru diedit".
const RECENTLY_EDITED_WINDOW_MS = 24 * 60 * 60 * 1000;

type StockFilter = "all" | "ready" | "out" | "archived";

export default async function AdminProductsPage({
  searchParams,
}: {
  searchParams: Promise<{ stock?: string; page?: string; q?: string; cat?: string; brand?: string }>;
}) {
  const { stock, page, q, cat, brand } = await searchParams;
  const stockFilter: StockFilter =
    stock === "ready" ? "ready"
    : stock === "out" ? "out"
    : stock === "archived" ? "archived"
    : "all";
  const currentPage = Math.max(1, Number(page) || 1);
  const search = (q ?? "").trim();
  const catSlug = (cat ?? "").trim();
  const brandSlug = (brand ?? "").trim();

  // ── Ambil kategori & brand untuk dropdown ────────────────────
  const [categories, brands] = await Promise.all([
    prisma.category.findMany({ orderBy: { name: "asc" } }),
    prisma.brand.findMany({ orderBy: { name: "asc" } }),
  ]);
  const activeCategory = categories.find((c) => c.slug === catSlug) ?? null;
  // Special: brand=none → produk tanpa brand
  const isNoBrand = brandSlug === "none";
  const activeBrand = isNoBrand ? null : brands.find((b) => b.slug === brandSlug) ?? null;

  // ── Build where clause ──────────────────────────────────────
  // - "out" hanya produk aktif yg habis (yg perlu di-restock).
  // - "archived" semua produk non-aktif (termasuk soft-archive hasil reset
  //   yg di-set stock=0).
  const stockWhere =
    stockFilter === "ready"    ? { isActive: true, stock: { gt: 0 } }
    : stockFilter === "out"    ? { isActive: true, stock: { equals: 0 } }
    : stockFilter === "archived" ? { isActive: false }
    : {};

  // Pakai matcher yang SAMA dengan katalog storefront/app (lib/search.ts):
  // query dipecah jadi token, tiap token dicocokkan ke nama produk, nama
  // brand, SKU varian, dan nilai opsi varian. Dulu `name contains search`
  // saja — "royal canin persian" atau pencarian by SKU/brand tidak ketemu
  // walau produknya ada.
  const searchWhere = (search ? productSearchWhere(search) : undefined) ?? {};

  const categoryWhere = activeCategory
    ? { categoryId: activeCategory.id }
    : {};

  const brandWhere = isNoBrand
    ? { brandId: null }
    : activeBrand
    ? { brandId: activeBrand.id }
    : {};

  const baseWhere = { ...searchWhere, ...categoryWhere, ...brandWhere, ...productIsVisibleWhere() };
  const where = { ...stockWhere, ...baseWhere };

  // ── Fetch counts + produk ────────────────────────────────────
  const [totalAll, totalReady, totalOut, totalArchived, filtered, products] = await Promise.all([
    prisma.product.count({ where: baseWhere }),
    prisma.product.count({ where: { ...baseWhere, isActive: true, stock: { gt: 0 } } }),
    prisma.product.count({ where: { ...baseWhere, isActive: true, stock: { equals: 0 } } }),
    prisma.product.count({ where: { ...baseWhere, isActive: false } }),
    prisma.product.count({ where }),
    prisma.product.findMany({
      where,
      // "Baru diedit/dibuat" ke atas: urut lastEditedAt desc (produk lama yang
      // belum pernah diedit = null → nulls last), lalu createdAt desc.
      orderBy: [
        { lastEditedAt: { sort: "desc", nulls: "last" } },
        { createdAt: "desc" },
      ],
      include: { category: true, brand: true },
      skip: (currentPage - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
    }),
  ]);

  const totalPages = Math.max(1, Math.ceil(filtered / PAGE_SIZE));
  const pageIds = products.map((p) => p.id);

  async function toggleActive(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const current = formData.get("isActive") === "true";
    await prisma.product.update({ where: { id }, data: { isActive: !current } });
    // Sync ke search index (is_active berubah → harus update)
    const { syncProduct } = await import("@/lib/search");
    await syncProduct(id).catch(() => {});
    revalidatePath("/admin/products");
    revalidatePath("/admin/stock");
    revalidatePath("/admin/dashboard");
  }

  async function deleteProduct(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));

    // Cek apakah produk pernah dipesan — kalau iya, refuse
    const orderCount = await prisma.orderItem.count({ where: { productId: id } });
    if (orderCount > 0) {
      throw new Error(
        `Produk pernah dipesan (${orderCount}× di order). Tidak bisa dihapus permanen — gunakan tombol Arsipkan/Nonaktifkan.`
      );
    }

    // Best-effort: hapus video Bunny sebelum hard-delete row. Bukan wajib
    // untuk kebenaran — cron GC (Task 9) tetap menyapu video orphan kalau
    // ini gagal, jadi tidak boleh menggagalkan/menunda delete produk.
    try {
      const productWithVideo = await prisma.product.findUnique({
        where: { id },
        select: { videoGuid: true },
      });
      if (productWithVideo?.videoGuid) {
        await deleteProductVideo(productWithVideo.videoGuid);
      }
    } catch {
      // best-effort, diabaikan — lihat komentar di atas.
    }

    // Hard delete — cascade akan handle variants, reviews, favorites, variantAttrs
    await prisma.product.delete({ where: { id } });

    // Hapus dari search index (non-blocking)
    const { deleteProductFromIndex } = await import("@/lib/search");
    await deleteProductFromIndex(id).catch(() => {});

    revalidatePath("/admin/products");
    revalidatePath("/admin/stock");
    revalidatePath("/admin/dashboard");
  }

  // ── Helper: build URL preserving semua filter aktif ──────────
  const buildHref = (overrides: { stock?: string; page?: number; cat?: string; brand?: string }) => {
    const sp = new URLSearchParams();
    const s = overrides.stock ?? stockFilter;
    if (s !== "all") sp.set("stock", s);
    const p = overrides.page ?? 1;
    if (p > 1) sp.set("page", String(p));
    if (search) sp.set("q", search);
    const c = "cat" in overrides ? overrides.cat : catSlug;
    if (c) sp.set("cat", c);
    const br = "brand" in overrides ? overrides.brand : brandSlug;
    if (br) sp.set("brand", br);
    const qs = sp.toString();
    return `/admin/products${qs ? `?${qs}` : ""}`;
  };

  const tabs: { key: StockFilter; label: string; count: number; color: string }[] = [
    { key: "all",      label: "Semua",      count: totalAll,      color: "bg-zinc-100 text-zinc-700" },
    { key: "ready",    label: "Stok Ready", count: totalReady,    color: "bg-green-100 text-green-700" },
    { key: "out",      label: "Stok Habis", count: totalOut,      color: "bg-red-100 text-red-700" },
    { key: "archived", label: "📦 Arsip",   count: totalArchived, color: "bg-amber-100 text-amber-700" },
  ];

  const hasActiveFilter = search || catSlug || brandSlug;

  return (
    <AdminPage maxWidth="xl">
      <PageHeader
        title="Produk"
        subtitle={`${totalAll} total · ${totalReady} ready · ${totalOut} habis · ${totalArchived} arsip${activeCategory ? ` · ${activeCategory.name}` : ""}`}
        actions={
          <>
            <Button href="/admin/products/import" variant="secondary" size="sm">
              ↧ Import
            </Button>
            <Button href="/admin/products/new" variant="primary" size="sm">
              + Tambah Produk
            </Button>
          </>
        }
      />

      {/* Search & Filter bar */}
      <form action="/admin/products" method="get" className="mt-5 space-y-3 md:mt-6">
        {/* Hidden: pertahankan stock filter */}
        {stockFilter !== "all" && (
          <input type="hidden" name="stock" value={stockFilter} />
        )}

        <div className="flex flex-col gap-2 md:flex-row md:flex-wrap">
          {/* Search input */}
          <input
            type="text"
            name="q"
            defaultValue={search}
            placeholder="Cari nama produk..."
            className="min-w-0 flex-1 rounded-full border border-zinc-300 px-4 py-2.5 text-sm outline-none focus:border-zinc-950"
          />

          <div className="grid grid-cols-2 gap-2 md:flex md:gap-2">
            {/* Kategori dropdown */}
            <select
              name="cat"
              defaultValue={catSlug}
              className="min-w-0 rounded-full border border-zinc-300 bg-white px-3 py-2.5 text-sm font-medium text-zinc-700 outline-none focus:border-zinc-950 md:px-4"
            >
              <option value="">Semua Kategori</option>
              {categories.map((c) => (
                <option key={c.id} value={c.slug}>
                  {c.name}
                </option>
              ))}
            </select>

            {/* Brand dropdown */}
            <select
              name="brand"
              defaultValue={brandSlug}
              className="min-w-0 rounded-full border border-zinc-300 bg-white px-3 py-2.5 text-sm font-medium text-zinc-700 outline-none focus:border-zinc-950 md:px-4"
            >
              <option value="">Semua Brand</option>
              <option value="none">— Tanpa brand —</option>
              {brands.map((b) => (
                <option key={b.id} value={b.slug}>
                  {b.name}
                </option>
              ))}
            </select>
          </div>

          <div className="flex gap-2">
            {/* Tombol Cari */}
            <button
              type="submit"
              className="flex-1 rounded-full bg-zinc-950 px-5 py-2.5 text-sm font-bold text-white hover:bg-zinc-800 md:flex-none"
            >
              Cari
            </button>

            {/* Reset (tampil kalau ada filter aktif) */}
            {hasActiveFilter && (
              <Link
                href={stockFilter !== "all" ? `/admin/products?stock=${stockFilter}` : "/admin/products"}
                className="flex-1 rounded-full border border-zinc-300 px-5 py-2.5 text-center text-sm font-semibold text-zinc-600 hover:bg-zinc-50 md:flex-none"
              >
                ✕ Reset
              </Link>
            )}
          </div>
        </div>

        {/* Active filter chips */}
        {hasActiveFilter && (
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs text-zinc-600">Filter aktif:</span>
            {search && (
              <span className="flex items-center gap-1 rounded-full bg-zinc-100 px-3 py-1 text-xs font-semibold text-zinc-700">
                🔍 "{search}"
                <Link
                  href={buildHref({ page: 1 }).replace(/[&?]q=[^&]*/g, "").replace(/&&/g, "&").replace(/^\?&/, "?")}
                  className="ml-1 text-zinc-400 hover:text-zinc-950"
                >
                  ×
                </Link>
              </span>
            )}
            {activeCategory && (
              <span className="flex items-center gap-1 rounded-full bg-natalo-100 px-3 py-1 text-xs font-semibold text-natalo-800">
                🏷️ {activeCategory.name}
                <Link
                  href={buildHref({ page: 1, cat: "" })}
                  className="ml-1 text-natalo-400 hover:text-natalo-800"
                >
                  ×
                </Link>
              </span>
            )}
            {(activeBrand || isNoBrand) && (
              <span className="flex items-center gap-1 rounded-full bg-purple-100 px-3 py-1 text-xs font-semibold text-purple-700">
                🏭 {activeBrand?.name ?? "Tanpa brand"}
                <Link
                  href={buildHref({ page: 1, brand: "" })}
                  className="ml-1 text-purple-400 hover:text-purple-700"
                >
                  ×
                </Link>
              </span>
            )}
          </div>
        )}
      </form>

      {/* Stock filter tabs */}
      <div className="-mx-4 mt-5 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:flex-wrap md:overflow-visible md:px-0">
        {tabs.map((tab) => {
          const active = stockFilter === tab.key;
          return (
            <Link
              key={tab.key}
              href={buildHref({ stock: tab.key, page: 1 })}
              className={`flex shrink-0 items-center gap-2 rounded-full border px-4 py-2 text-sm font-semibold transition ${
                active
                  ? "border-zinc-950 bg-zinc-950 text-white"
                  : "border-zinc-200 bg-white text-zinc-600 hover:border-zinc-400"
              }`}
            >
              {tab.label}
              <span
                className={`rounded-full px-2 py-0.5 text-[11px] font-bold ${
                  active ? "bg-white/20 text-white" : tab.color
                }`}
              >
                {tab.count}
              </span>
            </Link>
          );
        })}
      </div>

      {/* Product list */}
      <ProductSelectionProvider allIds={pageIds}>
      <div className="mt-5 overflow-hidden rounded-2xl border border-zinc-200 bg-white md:mt-6">
        <div className="hidden grid-cols-[28px_minmax(300px,1fr)_160px_120px_120px] items-center gap-4 border-b border-zinc-100 bg-zinc-50 px-4 py-3 text-xs font-bold uppercase tracking-wide text-zinc-400 lg:grid">
          <ProductSelectAll />
          <span>Produk</span>
          <span>Harga</span>
          <span>Stok</span>
          <span className="text-center">Aksi</span>
        </div>

        {products.length === 0 ? (
          <EmptyState
            icon={
              stockFilter === "out"
                ? "📭"
                : stockFilter === "ready"
                  ? "✨"
                  : stockFilter === "archived"
                    ? "🗄️"
                    : "🐾"
            }
            title={
              stockFilter === "out"
                ? "Tidak ada produk dengan stok habis"
                : stockFilter === "ready"
                  ? "Tidak ada produk yang siap dijual"
                  : stockFilter === "archived"
                    ? "Tidak ada produk di arsip"
                    : hasActiveFilter
                      ? "Tidak ada produk cocok dengan filter"
                      : "Belum ada produk"
            }
            description={
              hasActiveFilter
                ? "Coba reset filter atau ubah kriteria pencarian."
                : stockFilter === "all"
                  ? "Tambahkan produk pertama untuk mulai jualan."
                  : undefined
            }
            action={
              hasActiveFilter
                ? { label: "Reset semua filter", href: "/admin/products" }
                : !hasActiveFilter && stockFilter === "all"
                  ? { label: "Tambah produk pertama", href: "/admin/products/new" }
                  : undefined
            }
            size="full"
          />
        ) : (
          products.map((product) => {
            const hasDiscount =
              product.discountPrice !== null && product.discountPrice < product.price;
            const displayPrice = hasDiscount ? product.discountPrice! : product.price;
            const isOut = product.stock === 0;
            const isArchived = !product.isActive && product.stock > 0;
            const isRecentlyEdited =
              product.lastEditedAt != null &&
              Date.now() - product.lastEditedAt.getTime() < RECENTLY_EDITED_WINDOW_MS;

            const productMeta = (
              <div className="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
                {isRecentlyEdited && (
                  <span className="inline-flex items-center gap-1 rounded-full bg-natalo-50 px-2 py-0.5 text-[10px] font-semibold text-natalo-700">
                    <span className="h-1.5 w-1.5 rounded-full bg-natalo-500" aria-hidden="true" />
                    Baru diedit
                  </span>
                )}
                {product.category ? (
                  <Link
                    href={buildHref({ page: 1, cat: product.category.slug })}
                    className="font-medium text-natalo-600 hover:underline"
                  >
                    {product.category.name}
                  </Link>
                ) : (
                  <span className="text-zinc-300">Tanpa kategori</span>
                )}
                <span className="text-zinc-300">·</span>
                {product.brand ? (
                  <Link
                    href={buildHref({ page: 1, brand: product.brand.slug })}
                    className="flex items-center gap-1 font-medium text-purple-600 hover:underline"
                  >
                    🏭 {product.brand.name}
                    {product.brandAutoAssigned && (
                      <span className="rounded-full bg-amber-100 px-1.5 py-0.5 text-[9px] font-bold text-amber-700">
                        auto
                      </span>
                    )}
                  </Link>
                ) : (
                  <Link
                    href={`/admin/products/${product.id}/edit`}
                    className="text-zinc-400 italic hover:text-zinc-700 hover:underline"
                  >
                    + brand
                  </Link>
                )}
              </div>
            );

            const priceCell = product.hasVariants ? (
              <VariantInlineEditCell
                productId={product.id}
                productName={product.name}
                field="price"
                initialValue={product.price}
              />
            ) : (
              <InlineEditCell
                productId={product.id}
                field="price"
                initialValue={product.price}
              />
            );

            const stockCell = product.hasVariants ? (
              <VariantInlineEditCell
                productId={product.id}
                productName={product.name}
                field="stock"
                initialValue={product.stock}
              />
            ) : (
              <InlineEditCell
                productId={product.id}
                field="stock"
                initialValue={product.stock}
              />
            );

            const editLink = (
              <Button
                href={`/admin/products/${product.id}/edit`}
                variant="secondary"
                size="sm"
                fullWidth
              >
                Edit
              </Button>
            );

            const toggleForm = (
              <form action={toggleActive}>
                <input type="hidden" name="id" value={product.id} />
                <input type="hidden" name="isActive" value={String(product.isActive)} />
                <button
                  type="submit"
                  className={`w-full rounded-full border px-3 py-2 text-xs font-bold transition ${
                    isArchived
                      ? "border-amber-300 bg-amber-50 text-amber-700 hover:bg-amber-100"
                      : "border-zinc-300 hover:bg-zinc-50"
                  }`}
                >
                  {isArchived
                    ? "Keluarkan arsip"
                    : product.isActive
                    ? (product.stock > 0 ? "Arsipkan" : "Nonaktifkan")
                    : "Aktifkan"}
                </button>
              </form>
            );

            const deleteForm = (
              <form action={deleteProduct}>
                <input type="hidden" name="id" value={product.id} />
                <ConfirmSubmitButton
                  className="w-full rounded-full border border-red-200 px-3 py-2 text-xs font-bold text-red-600 hover:bg-red-50"
                  message={`Hapus permanen produk "${product.name}"? Tindakan ini tidak bisa dibatalkan. Jika produk pernah dipesan, gunakan Arsipkan saja.`}
                >
                  🗑️ Hapus
                </ConfirmSubmitButton>
              </form>
            );

            return (
              <div
                key={product.id}
                className={`border-b border-zinc-100 last:border-b-0 ${
                  product.isActive ? "bg-white" : "bg-zinc-50 opacity-70"
                }`}
              >
                {/* Mobile card */}
                <div className="p-4 lg:hidden">
                  <div className="flex gap-3">
                    <div className="flex items-center pt-1">
                      <ProductRowCheckbox id={product.id} />
                    </div>
                    <div className="relative h-16 w-16 shrink-0 overflow-hidden rounded-lg bg-zinc-100">
                      {product.imageUrl ? (
                        <Image
                          src={product.imageUrl}
                          alt={product.name}
                          fill
                          sizes="64px"
                          className="object-cover"
                        />
                      ) : (
                        <div className="flex h-full w-full items-center justify-center text-xs font-bold text-zinc-300">
                          IMG
                        </div>
                      )}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start gap-2">
                        <Link
                          href={`/admin/products/${product.id}/edit`}
                          className="line-clamp-2 flex-1 font-semibold leading-snug text-zinc-950"
                        >
                          {product.name}
                        </Link>
                        {isArchived ? (
                          <span className="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-semibold text-amber-700">
                            📦 Arsip
                          </span>
                        ) : !product.isActive ? (
                          <span className="shrink-0 rounded-full bg-zinc-200 px-2 py-0.5 text-[10px] font-semibold text-zinc-600">
                            Nonaktif
                          </span>
                        ) : null}
                      </div>
                      {productMeta}
                    </div>
                  </div>

                  <div className="mt-3 grid grid-cols-2 gap-2 border-t border-zinc-100 pt-3">
                    <div>
                      <p className="px-1 text-[10px] font-bold uppercase tracking-wide text-zinc-400">Harga</p>
                      <div className="mt-1">{priceCell}</div>
                      {hasDiscount && !product.hasVariants && (
                        <p className="mt-1 px-2 text-[11px] text-natalo-700">
                          Diskon: {formatRupiah(product.discountPrice!)}
                        </p>
                      )}
                    </div>
                    <div>
                      <p className="px-1 text-[10px] font-bold uppercase tracking-wide text-zinc-400">Stok</p>
                      <div className="mt-1">{stockCell}</div>
                    </div>
                  </div>

                  <div className="mt-3 grid grid-cols-3 gap-2">
                    {editLink}
                    {toggleForm}
                    {deleteForm}
                  </div>
                </div>

                {/* Desktop grid row */}
                <div className="hidden grid-cols-[28px_minmax(300px,1fr)_160px_120px_120px] items-start gap-4 px-4 py-5 lg:grid">
                  <div className="flex items-center pt-1">
                    <ProductRowCheckbox id={product.id} />
                  </div>
                  <div className="flex min-w-0 gap-3">
                    <div className="relative h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-zinc-100">
                      {product.imageUrl ? (
                        <Image
                          src={product.imageUrl}
                          alt={product.name}
                          fill
                          sizes="56px"
                          className="object-cover"
                        />
                      ) : (
                        <div className="flex h-full w-full items-center justify-center text-xs font-bold text-zinc-300">
                          IMG
                        </div>
                      )}
                    </div>
                    <div className="min-w-0">
                      <div className="flex items-start gap-2">
                        <Link
                          href={`/admin/products/${product.id}/edit`}
                          className="line-clamp-2 font-semibold leading-snug text-zinc-950 hover:text-natalo-700"
                        >
                          {product.name}
                        </Link>
                        {isArchived ? (
                          <span className="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold text-amber-700">
                            📦 Arsip
                          </span>
                        ) : !product.isActive ? (
                          <span className="shrink-0 rounded-full bg-zinc-200 px-2 py-0.5 text-[11px] font-semibold text-zinc-600">
                            Nonaktif
                          </span>
                        ) : null}
                      </div>
                      {productMeta}
                    </div>
                  </div>

                  <div className="pt-1">
                    {priceCell}
                    {hasDiscount && !product.hasVariants && (
                      <p className="mt-1 px-2 text-xs text-natalo-700">
                        Diskon: {formatRupiah(product.discountPrice!)}
                      </p>
                    )}
                  </div>

                  <div className="pt-1">{stockCell}</div>

                  <div className="flex flex-col items-stretch gap-2">
                    {editLink}
                    {toggleForm}
                    {deleteForm}
                  </div>
                </div>
              </div>
            );
          })
        )}
      </div>
      <ProductBulkBar />
      </ProductSelectionProvider>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-zinc-500">
            Halaman {currentPage} dari {totalPages} · {filtered} produk
          </p>
          <div className="flex gap-2">
            {currentPage > 1 && (
              <Link
                href={buildHref({ page: currentPage - 1 })}
                className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-semibold hover:bg-zinc-50"
              >
                ← Sebelumnya
              </Link>
            )}
            {currentPage < totalPages && (
              <Link
                href={buildHref({ page: currentPage + 1 })}
                className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-semibold hover:bg-zinc-50"
              >
                Selanjutnya →
              </Link>
            )}
          </div>
        </div>
      )}
    </AdminPage>
  );
}
