import Image from "next/image";
import Link from "next/link";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { InlineEditCell } from "@/components/admin/InlineEditCell";
import { VariantInlineEditCell } from "@/components/admin/VariantInlineEditCell";
import { ConfirmSubmitButton } from "@/components/ConfirmSubmitButton";

const PAGE_SIZE = 50;

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
  const stockWhere =
    stockFilter === "ready"    ? { isActive: true, stock: { gt: 0 } }
    : stockFilter === "out"    ? { stock: { equals: 0 } }
    : stockFilter === "archived" ? { isActive: false, stock: { gt: 0 } }
    : {};

  const searchWhere = search
    ? { name: { contains: search, mode: "insensitive" as const } }
    : {};

  const categoryWhere = activeCategory
    ? { categoryId: activeCategory.id }
    : {};

  const brandWhere = isNoBrand
    ? { brandId: null }
    : activeBrand
    ? { brandId: activeBrand.id }
    : {};

  const baseWhere = { ...searchWhere, ...categoryWhere, ...brandWhere };
  const where = { ...stockWhere, ...baseWhere };

  // ── Fetch counts + produk ────────────────────────────────────
  const [totalAll, totalReady, totalOut, totalArchived, filtered, products] = await Promise.all([
    prisma.product.count({ where: baseWhere }),
    prisma.product.count({ where: { ...baseWhere, isActive: true, stock: { gt: 0 } } }),
    prisma.product.count({ where: { ...baseWhere, stock: { equals: 0 } } }),
    prisma.product.count({ where: { ...baseWhere, isActive: false, stock: { gt: 0 } } }),
    prisma.product.count({ where }),
    prisma.product.findMany({
      where,
      orderBy: { createdAt: "desc" },
      include: { category: true, brand: true },
      skip: (currentPage - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
    }),
  ]);

  const totalPages = Math.max(1, Math.ceil(filtered / PAGE_SIZE));

  async function toggleActive(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const current = formData.get("isActive") === "true";
    await prisma.product.update({ where: { id }, data: { isActive: !current } });
    // Sync ke search index (is_active berubah → harus update)
    const { syncProduct } = await import("@/lib/search");
    await syncProduct(id).catch(() => {});
    revalidatePath("/admin/products");
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

    // Hard delete — cascade akan handle variants, reviews, favorites, variantAttrs
    await prisma.product.delete({ where: { id } });

    // Hapus dari search index (non-blocking)
    const { deleteProductFromIndex } = await import("@/lib/search");
    await deleteProductFromIndex(id).catch(() => {});

    revalidatePath("/admin/products");
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
    <div className="mx-auto max-w-6xl px-4 py-10">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <Link href="/admin" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
            Kembali ke dashboard
          </Link>
          <h1 className="mt-2 text-3xl font-black tracking-tight text-zinc-950">Produk</h1>
          <p className="mt-1 text-sm text-zinc-500">
            {totalAll} total · {totalReady} ready · {totalOut} habis · {totalArchived} arsip
            {activeCategory && (
              <span className="ml-2 rounded-full bg-natalo-100 px-2 py-0.5 text-xs font-bold text-natalo-700">
                {activeCategory.name}
              </span>
            )}
          </p>
        </div>
        <Link
          href="/admin/products/new"
          className="rounded-full bg-zinc-950 px-5 py-3 text-sm font-bold text-white"
        >
          + Tambah produk
        </Link>
      </div>

      {/* Search & Filter bar */}
      <form action="/admin/products" method="get" className="mt-6 space-y-3">
        {/* Hidden: pertahankan stock filter */}
        {stockFilter !== "all" && (
          <input type="hidden" name="stock" value={stockFilter} />
        )}

        <div className="flex flex-wrap gap-2">
          {/* Search input */}
          <input
            type="text"
            name="q"
            defaultValue={search}
            placeholder="Cari nama produk..."
            className="min-w-0 flex-1 rounded-full border border-zinc-300 px-4 py-2.5 text-sm outline-none focus:border-zinc-950"
          />

          {/* Kategori dropdown */}
          <select
            name="cat"
            defaultValue={catSlug}
            className="rounded-full border border-zinc-300 bg-white px-4 py-2.5 text-sm font-medium text-zinc-700 outline-none focus:border-zinc-950"
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
            className="rounded-full border border-zinc-300 bg-white px-4 py-2.5 text-sm font-medium text-zinc-700 outline-none focus:border-zinc-950"
          >
            <option value="">Semua Brand</option>
            <option value="none">— Tanpa brand —</option>
            {brands.map((b) => (
              <option key={b.id} value={b.slug}>
                {b.name}
              </option>
            ))}
          </select>

          {/* Tombol Cari */}
          <button
            type="submit"
            className="rounded-full bg-zinc-950 px-5 py-2.5 text-sm font-bold text-white hover:bg-zinc-800"
          >
            Cari
          </button>

          {/* Reset (tampil kalau ada filter aktif) */}
          {hasActiveFilter && (
            <Link
              href={stockFilter !== "all" ? `/admin/products?stock=${stockFilter}` : "/admin/products"}
              className="rounded-full border border-zinc-300 px-5 py-2.5 text-sm font-semibold text-zinc-600 hover:bg-zinc-50"
            >
              ✕ Reset filter
            </Link>
          )}
        </div>

        {/* Active filter chips */}
        {hasActiveFilter && (
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs text-zinc-400">Filter aktif:</span>
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
      <div className="mt-5 flex flex-wrap gap-2">
        {tabs.map((tab) => {
          const active = stockFilter === tab.key;
          return (
            <Link
              key={tab.key}
              href={buildHref({ stock: tab.key, page: 1 })}
              className={`flex items-center gap-2 rounded-full border px-4 py-2 text-sm font-semibold transition ${
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
      <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
        <div className="grid grid-cols-[minmax(320px,1fr)_160px_120px_120px] gap-4 border-b border-zinc-100 bg-zinc-50 px-4 py-3 text-xs font-bold uppercase tracking-wide text-zinc-400">
          <span>Produk</span>
          <span>Harga</span>
          <span>Stok</span>
          <span className="text-center">Aksi</span>
        </div>

        {products.length === 0 ? (
          <div className="p-12 text-center">
            <span className="text-4xl">
              {stockFilter === "out" ? "📭"
                : stockFilter === "ready" ? "✨"
                : stockFilter === "archived" ? "🗄️"
                : "🐾"}
            </span>
            <p className="mt-3 text-sm text-zinc-500">
              {stockFilter === "out"
                ? "Tidak ada produk dengan stok habis."
                : stockFilter === "ready"
                ? "Tidak ada produk yang siap dijual."
                : stockFilter === "archived"
                ? "Tidak ada produk di arsip."
                : hasActiveFilter
                ? "Tidak ada produk yang cocok dengan filter ini."
                : "Belum ada produk."}
            </p>
            {!hasActiveFilter && stockFilter === "all" && (
              <Link
                href="/admin/products/new"
                className="mt-4 inline-flex rounded-full bg-zinc-950 px-5 py-2.5 text-sm font-bold text-white"
              >
                Tambah sekarang
              </Link>
            )}
            {hasActiveFilter && (
              <Link
                href="/admin/products"
                className="mt-4 inline-flex rounded-full border border-zinc-300 px-5 py-2.5 text-sm font-semibold text-zinc-700 hover:bg-zinc-50"
              >
                Reset semua filter
              </Link>
            )}
          </div>
        ) : (
          products.map((product) => {
            const hasDiscount =
              product.discountPrice !== null && product.discountPrice < product.price;
            const displayPrice = hasDiscount ? product.discountPrice! : product.price;
            const isOut = product.stock === 0;
            const isArchived = !product.isActive && product.stock > 0;

            return (
              <div
                key={product.id}
                className={`grid grid-cols-[minmax(320px,1fr)_160px_120px_120px] gap-4 border-b border-zinc-100 px-4 py-5 last:border-b-0 ${
                  product.isActive ? "bg-white" : "bg-zinc-50 opacity-70"
                }`}
              >
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
                    <div className="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
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
                  </div>
                </div>

                <div className="pt-1">
                  {product.hasVariants ? (
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
                  )}
                  {hasDiscount && !product.hasVariants && (
                    <p className="mt-1 px-2 text-xs text-natalo-700">
                      Diskon: {formatRupiah(product.discountPrice!)}
                    </p>
                  )}
                </div>

                <div className="pt-1">
                  {product.hasVariants ? (
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
                  )}
                </div>

                <div className="flex flex-col items-stretch gap-2">
                  <Link
                    href={`/admin/products/${product.id}/edit`}
                    className="rounded-full border border-zinc-300 px-3 py-2 text-center text-xs font-bold hover:bg-zinc-50"
                  >
                    Edit
                  </Link>
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
                  <form action={deleteProduct}>
                    <input type="hidden" name="id" value={product.id} />
                    <ConfirmSubmitButton
                      className="w-full rounded-full border border-red-200 px-3 py-2 text-xs font-bold text-red-600 hover:bg-red-50"
                      message={`Hapus permanen produk "${product.name}"? Tindakan ini tidak bisa dibatalkan. Jika produk pernah dipesan, gunakan Arsipkan saja.`}
                    >
                      🗑️ Hapus
                    </ConfirmSubmitButton>
                  </form>
                </div>
              </div>
            );
          })
        )}
      </div>

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
    </div>
  );
}
