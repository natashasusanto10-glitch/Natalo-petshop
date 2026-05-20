/**
 * /admin/diskon/promo-toko — List Promo Toko (drill-down dari hub)
 *
 * Detail semua ProductDiscount campaigns. Filter tab (Akan Datang /
 * Sedang Berlangsung / Kedaluwarsa) + action per row.
 */
import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";

export const dynamic = "force-dynamic";

type StatusFilter = "all" | "ongoing" | "upcoming" | "expired";

function statusOf(
  startsAt: Date,
  endsAt: Date,
  isActive: boolean,
): "ongoing" | "upcoming" | "expired" {
  const now = new Date();
  if (!isActive) return "expired";
  if (endsAt < now) return "expired";
  if (startsAt > now) return "upcoming";
  return "ongoing";
}

function formatDateTime(d: Date) {
  return d.toLocaleString("id-ID", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export default async function PromoTokoListPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; q?: string }>;
}) {
  const { status: statusRaw, q } = await searchParams;
  const status: StatusFilter =
    statusRaw === "ongoing" ||
    statusRaw === "upcoming" ||
    statusRaw === "expired"
      ? statusRaw
      : "all";
  const search = q?.trim() ?? "";

  const now = new Date();
  const whereStatus =
    status === "ongoing"
      ? { isActive: true, startsAt: { lte: now }, endsAt: { gt: now } }
      : status === "upcoming"
        ? { isActive: true, startsAt: { gt: now } }
        : status === "expired"
          ? {
              OR: [{ isActive: false }, { endsAt: { lt: now } }],
            }
          : {};

  const promos = await prisma.productDiscount.findMany({
    where: {
      ...whereStatus,
      ...(search ? { name: { contains: search, mode: "insensitive" } } : {}),
    },
    orderBy: [{ isActive: "desc" }, { createdAt: "desc" }],
    take: 100,
  });

  // Fetch thumbnail produk pertama untuk display
  const allProductIds = Array.from(
    new Set(promos.flatMap((p) => p.productIds.slice(0, 3))),
  );
  const productMap = new Map<string, { name: string; imageUrl: string | null }>();
  if (allProductIds.length > 0) {
    const productsForPromos = await prisma.product.findMany({
      where: { id: { in: allProductIds } },
      select: { id: true, name: true, imageUrl: true },
    });
    for (const p of productsForPromos) {
      productMap.set(p.id, { name: p.name, imageUrl: p.imageUrl });
    }
  }

  // Counts untuk tab
  const [ongoingCount, upcomingCount, expiredCount, totalCount] =
    await Promise.all([
      prisma.productDiscount.count({
        where: {
          isActive: true,
          startsAt: { lte: now },
          endsAt: { gt: now },
        },
      }),
      prisma.productDiscount.count({
        where: { isActive: true, startsAt: { gt: now } },
      }),
      prisma.productDiscount.count({
        where: {
          OR: [{ isActive: false }, { endsAt: { lt: now } }],
        },
      }),
      prisma.productDiscount.count(),
    ]);

  return (
    <div className="mx-auto max-w-7xl px-4 py-5 md:px-8 md:py-10">
      <Link
        href="/admin/diskon"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke Buat Diskon
      </Link>
      <div className="mt-2 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
            🏷 Promo Toko
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            {totalCount} campaign promosi
          </p>
        </div>
        <Link
          href="/admin/diskon/promo-toko/new"
          className="rounded-full bg-natalo-600 px-5 py-2.5 text-sm font-bold text-white hover:bg-natalo-700"
        >
          + Buat Promo Toko
        </Link>
      </div>

      {/* Tab filter */}
      <div className="mt-6 flex flex-wrap gap-2 border-b border-zinc-200">
        <TabLink
          label={`Semua (${totalCount})`}
          active={status === "all"}
          href="/admin/diskon/promo-toko"
        />
        <TabLink
          label={`Sedang Berjalan (${ongoingCount})`}
          active={status === "ongoing"}
          href="/admin/diskon/promo-toko?status=ongoing"
        />
        <TabLink
          label={`Akan Datang (${upcomingCount})`}
          active={status === "upcoming"}
          href="/admin/diskon/promo-toko?status=upcoming"
        />
        <TabLink
          label={`Kedaluwarsa (${expiredCount})`}
          active={status === "expired"}
          href="/admin/diskon/promo-toko?status=expired"
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
          placeholder="🔍 Cari nama promosi..."
          className="flex-1 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-natalo-600"
        />
        <button
          type="submit"
          className="rounded-xl bg-natalo-600 px-5 py-2.5 text-sm font-bold text-white hover:bg-natalo-700"
        >
          Cari
        </button>
      </form>

      {/* List */}
      <div className="mt-4 overflow-hidden rounded-2xl border border-zinc-200">
        {promos.length === 0 ? (
          <div className="p-12 text-center">
            <p className="text-3xl">🏷</p>
            <p className="mt-3 text-sm font-semibold text-zinc-700">
              {search
                ? "Tidak ada promo cocok dengan pencarian."
                : status === "ongoing"
                  ? "Belum ada promo yang sedang berjalan."
                  : status === "upcoming"
                    ? "Belum ada promo yang akan datang."
                    : status === "expired"
                      ? "Belum ada promo yang kedaluwarsa."
                      : "Belum ada promo toko."}
            </p>
            {!search && status === "all" && (
              <Link
                href="/admin/diskon/promo-toko/new"
                className="mt-4 inline-block rounded-full bg-natalo-600 px-5 py-2.5 text-sm font-bold text-white"
              >
                Buat Promo Toko
              </Link>
            )}
          </div>
        ) : (
          <div className="divide-y divide-zinc-100">
            {promos.map((promo) => {
              const promoStatus = statusOf(
                promo.startsAt,
                promo.endsAt,
                promo.isActive,
              );
              const thumbnails = promo.productIds
                .slice(0, 4)
                .map((pid) => productMap.get(pid))
                .filter((p): p is { name: string; imageUrl: string | null } => !!p);

              return (
                <div
                  key={promo.id}
                  className="flex flex-wrap items-start gap-4 p-4 hover:bg-zinc-50/50 md:flex-nowrap"
                >
                  {/* Left: status + name + discount info */}
                  <div className="min-w-0 flex-1">
                    <StatusBadge status={promoStatus} />
                    <p className="mt-1 font-semibold text-zinc-900">
                      {promo.name}
                    </p>
                    <p className="mt-0.5 text-xs text-zinc-500">
                      {promo.discountType === "PERCENTAGE"
                        ? `Diskon ${promo.discountValue}%`
                        : `Diskon ${formatRupiah(promo.discountValue)}`}
                      {promo.maxDiscountCap &&
                        ` (max ${formatRupiah(promo.maxDiscountCap)})`}
                    </p>
                  </div>

                  {/* Mid: product thumbnails */}
                  <div className="flex items-center gap-1">
                    {thumbnails.slice(0, 3).map((p, i) =>
                      p.imageUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          key={i}
                          src={p.imageUrl}
                          alt={p.name}
                          title={p.name}
                          className="h-10 w-10 rounded border border-zinc-200 object-cover"
                        />
                      ) : (
                        <div
                          key={i}
                          className="h-10 w-10 rounded border border-zinc-200 bg-zinc-100"
                        />
                      ),
                    )}
                    {promo.productIds.length > 3 && (
                      <span className="ml-1 text-xs font-bold text-zinc-400">
                        +{promo.productIds.length - 3}
                      </span>
                    )}
                  </div>

                  {/* Right: periode + actions */}
                  <div className="text-right text-xs text-zinc-600">
                    <p>{formatDateTime(promo.startsAt)}</p>
                    <p>→ {formatDateTime(promo.endsAt)}</p>
                    <div className="mt-2 flex justify-end gap-2">
                      <Link
                        href={`/admin/diskon/promo-toko/${promo.id}/edit`}
                        className="text-sm font-semibold text-natalo-600 hover:text-natalo-700"
                      >
                        {promoStatus === "expired" ? "Lihat" : "Ubah"}
                      </Link>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
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

function StatusBadge({
  status,
}: {
  status: "ongoing" | "upcoming" | "expired";
}) {
  const styles = {
    ongoing: "bg-green-50 text-green-700",
    upcoming: "bg-amber-50 text-amber-700",
    expired: "bg-zinc-100 text-zinc-500",
  };
  const labels = {
    ongoing: "Sedang Berjalan",
    upcoming: "Akan Datang",
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
