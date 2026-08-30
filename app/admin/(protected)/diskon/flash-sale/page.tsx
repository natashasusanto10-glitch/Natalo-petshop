/**
 * /admin/diskon/flash-sale — List Flash Sale (drill-down dari hub)
 *
 * Tampilkan semua produk yang sedang/pernah punya flashSaleEndsAt.
 * Filter tab Sedang Berjalan / Akan Datang (jarang — biasanya start
 * langsung saat dibuat) / Kedaluwarsa.
 *
 * Tidak ada "edit Flash Sale" — admin ubah flash sale lewat edit
 * produk individual (klik baris produk → /admin/products/{id}/edit).
 * Untuk akhiri lebih awal, edit produk + clear flashSaleEndsAt.
 */
import Link from "next/link";
import { AdminPage, Button, ResultCount } from "@/components/admin/ui";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { productSearchWhere } from "@/lib/search";
import { EndFlashSaleButton } from "@/components/admin/EndFlashSaleButton";

export const dynamic = "force-dynamic";

const FLASH_SALE_LIST_LIMIT = 100;

type StatusFilter = "all" | "ongoing" | "expired";

function statusOf(endsAt: Date | null): "ongoing" | "expired" {
  if (!endsAt) return "expired";
  return endsAt > new Date() ? "ongoing" : "expired";
}

function formatDateTime(d: Date | null) {
  if (!d) return "—";
  return d.toLocaleString("id-ID", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export default async function FlashSaleListPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; q?: string }>;
}) {
  const { status: statusRaw, q } = await searchParams;
  const status: StatusFilter =
    statusRaw === "ongoing" || statusRaw === "expired" ? statusRaw : "all";
  const search = q?.trim() ?? "";

  const now = new Date();
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  // For "expired" filter, only show last 30 hari history (avoid pulling
  // years of history).
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

  const whereStatus =
    status === "ongoing"
      ? { flashSaleEndsAt: { gt: now } }
      : status === "expired"
        ? { flashSaleEndsAt: { lt: now, gt: thirtyDaysAgo } }
        : { flashSaleEndsAt: { gt: sevenDaysAgo } }; // "all" default — active + recent 7d

  // Satu objek `where` dipakai bersama oleh daftar DAN penghitungnya, supaya
  // angka "menampilkan N dari M" tidak bisa lepas dari filter yang aktif.
  const listWhere = {
    ...whereStatus,
    // Matcher sama dengan katalog: token multi-kata + nama brand + SKU.
    ...((search ? productSearchWhere(search) : undefined) ?? {}),
  };

  const products = await prisma.product.findMany({
    where: listWhere,
    orderBy: { flashSaleEndsAt: "desc" },
    take: FLASH_SALE_LIST_LIMIT,
    select: {
      id: true,
      name: true,
      imageUrl: true,
      slug: true,
      price: true,
      discountPrice: true,
      stock: true,
      flashSaleEndsAt: true,
    },
  });

  const [matchingCount, ongoingCount, expiredCount, totalCount] = await Promise.all([
    prisma.product.count({ where: listWhere }),
    prisma.product.count({ where: { flashSaleEndsAt: { gt: now } } }),
    prisma.product.count({
      where: { flashSaleEndsAt: { lt: now, gt: thirtyDaysAgo } },
    }),
    prisma.product.count({ where: { flashSaleEndsAt: { not: null } } }),
  ]);

  return (
    <AdminPage>
      <Link
        href="/admin/diskon"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke Buat Diskon
      </Link>
      <div className="mt-2 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
            ⚡ Flash Sale
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            {totalCount} produk pernah masuk Flash Sale (history disimpan)
          </p>
        </div>
        <Link
          href="/admin/diskon/flash-sale/new"
          className="rounded-full bg-amber-600 px-5 py-2.5 text-sm font-bold text-white hover:bg-amber-700"
        >
          + Buat Flash Sale
        </Link>
      </div>

      {/* Tab filter */}
      <div className="mt-6 flex flex-wrap gap-2 border-b border-zinc-200">
        <TabLink
          label={`Semua`}
          active={status === "all"}
          href="/admin/diskon/flash-sale"
        />
        <TabLink
          label={`Sedang Berjalan (${ongoingCount})`}
          active={status === "ongoing"}
          href="/admin/diskon/flash-sale?status=ongoing"
        />
        <TabLink
          label={`Kedaluwarsa (${expiredCount})`}
          active={status === "expired"}
          href="/admin/diskon/flash-sale?status=expired"
        />
      </div>

      {/* Search */}
      <form className="mt-4 flex gap-2" method="GET">
        {status !== "all" && (
          <input type="hidden" name="status" value={status} />
        )}
        <input
          type="text"
          name="q"
          defaultValue={search}
          placeholder="🔍 Cari nama produk..."
          className="flex-1 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-natalo-600"
        />
        <Button type="submit">Cari</Button>
      </form>

      {/* List */}
      <div className="mt-4">
        <ResultCount
          shown={products.length}
          total={matchingCount}
          noun="produk Flash Sale"
        />
      </div>
      <div className="overflow-hidden rounded-2xl border border-zinc-200">
        {products.length === 0 ? (
          <div className="p-12 text-center">
            <p className="text-3xl">⚡</p>
            <p className="mt-3 text-sm font-semibold text-zinc-700">
              {search
                ? "Tidak ada produk Flash Sale cocok dengan pencarian."
                : status === "ongoing"
                  ? "Belum ada Flash Sale yang sedang berjalan."
                  : status === "expired"
                    ? "Belum ada Flash Sale yang kedaluwarsa."
                    : "Belum ada Flash Sale."}
            </p>
            {!search && status === "all" && (
              <Link
                href="/admin/diskon/flash-sale/new"
                className="mt-4 inline-block rounded-full bg-amber-600 px-5 py-2.5 text-sm font-bold text-white"
              >
                Buat Flash Sale
              </Link>
            )}
          </div>
        ) : (
          <div className="divide-y divide-zinc-100">
            {products.map((p) => {
              const promoStatus = statusOf(p.flashSaleEndsAt);
              const discountPercent =
                p.discountPrice && p.price > 0
                  ? Math.round(
                      ((p.price - p.discountPrice) / p.price) * 100,
                    )
                  : 0;
              return (
                <div
                  key={p.id}
                  className="flex flex-wrap items-center gap-4 p-4 hover:bg-zinc-50/50 md:flex-nowrap"
                >
                  {/* Image */}
                  {p.imageUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={p.imageUrl}
                      alt={p.name}
                      className="h-14 w-14 shrink-0 rounded border border-zinc-200 object-cover"
                    />
                  ) : (
                    <div className="h-14 w-14 shrink-0 rounded border border-zinc-200 bg-zinc-100" />
                  )}

                  {/* Info */}
                  <div className="min-w-0 flex-1">
                    <StatusBadge status={promoStatus} />
                    <p className="mt-1 truncate font-semibold text-zinc-900">
                      {p.name}
                    </p>
                    <p className="mt-0.5 text-xs text-zinc-500">
                      {p.discountPrice ? (
                        <>
                          <span className="line-through">
                            {formatRupiah(p.price)}
                          </span>{" "}
                          →{" "}
                          <span className="font-bold text-red-600">
                            {formatRupiah(p.discountPrice)}
                          </span>
                          {discountPercent > 0 && (
                            <span className="ml-1 inline-block rounded bg-red-50 px-1.5 py-0.5 text-[10px] font-bold text-red-600">
                              -{discountPercent}%
                            </span>
                          )}
                        </>
                      ) : (
                        formatRupiah(p.price)
                      )}
                      {" • Stok: "}
                      {p.stock}
                    </p>
                  </div>

                  {/* Periode + actions */}
                  <div className="text-right text-xs text-zinc-600">
                    <p>Berakhir:</p>
                    <p className="font-semibold text-zinc-900">
                      {formatDateTime(p.flashSaleEndsAt)}
                    </p>
                    <div className="mt-2 flex items-center justify-end gap-3">
                      <Link
                        href={`/admin/products/${p.id}/edit`}
                        className="text-sm font-semibold text-natalo-600 hover:text-natalo-700"
                      >
                        Lihat
                      </Link>
                      {promoStatus === "ongoing" && (
                        <EndFlashSaleButton
                          productId={p.id}
                          productName={p.name}
                        />
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </AdminPage>
  );
}

function TabLink({
  label,
  active,
  href,
}: {
  label: string;
  active: boolean;
  href: string;
}) {
  return (
    <Link
      href={href}
      className={`border-b-2 px-3 py-2 text-sm font-bold transition ${
        active
          ? "border-natalo-600 text-natalo-700"
          : "border-transparent text-zinc-500 hover:text-zinc-900"
      }`}
    >
      {label}
    </Link>
  );
}

function StatusBadge({ status }: { status: "ongoing" | "expired" }) {
  const styles = {
    ongoing: "bg-green-50 text-green-700",
    expired: "bg-zinc-100 text-zinc-500",
  };
  const labels = {
    ongoing: "Sedang Berjalan",
    expired: "Telah Berakhir",
  };
  return (
    <span
      className={`inline-block rounded-md px-2 py-0.5 text-[10px] font-bold ${styles[status]}`}
    >
      {labels[status]}
    </span>
  );
}
