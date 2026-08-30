import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { ConfirmSubmitButton } from "@/components/ConfirmSubmitButton";
import { voucherUsageLimitLabel } from "@/lib/voucher-helpers";
import {
  isFreeShippingVoucher,
  isLoyaltyClaimVoucher,
  voucherKindLabel,
  voucherTargetUserLabel,
} from "@/lib/voucher-kind";
import {
  PageHeader,
  StatCard,
  EmptyState,
  Badge,
  AdminPage,
  Button,
} from "@/components/admin/ui";
import { voucherSearchWhere } from "@/lib/admin-search";
import { parsePageParam } from "@/lib/admin/pagination";
import {
  LOYALTY_VOUCHER_WHERE,
  NON_LOYALTY_VOUCHER_WHERE,
  tallyVoucherCategories,
} from "@/lib/admin/voucher-categories";

const PAGE_SIZE = 20;

export default async function AdminVouchersPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; q?: string }>;
}) {
  const { page: pageStr, q } = await searchParams;
  const page = parsePageParam(pageStr);
  const search = q?.trim() ?? "";

  const searchWhere = voucherSearchWhere(search);
  const where = searchWhere ? { AND: searchWhere.AND } : {};

  // Voucher loyalty dibuat PER PENGGUNA, jadi jumlah barisnya tumbuh mengikuti
  // member — bukan campaign. Sebelumnya halaman ini menarik SEMUANYA lalu
  // menghitung kategori di JavaScript; sekarang hitungannya di database dan
  // barisnya dipaginasi.
  const [vouchers, total, loyaltyCount, nonLoyaltyGroups] = await Promise.all([
    prisma.voucher.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
    }),
    prisma.voucher.count({ where }),
    prisma.voucher.count({ where: LOYALTY_VOUCHER_WHERE }),
    prisma.voucher.groupBy({
      by: ["kind", "sourceType"],
      where: NON_LOYALTY_VOUCHER_WHERE,
      _count: { _all: true },
    }),
  ]);

  const totalPages = Math.ceil(total / PAGE_SIZE);
  // Halaman melampaui batas (mis. voucher terhapus saat admin di halaman 2,
  // atau `?page=99` diketik manual). Tanpa ini daftar tampak kosong dengan
  // pesan "belum ada voucher" padahal kartu statistik menunjukkan ratusan —
  // pesan yang saling bertentangan lebih membingungkan daripada nol hasil.
  const pageBeyondEnd = total > 0 && page > totalPages;

  // Pencarian ikut terbawa saat pindah halaman — kalau tidak, halaman 2
  // diam-diam kembali menampilkan seluruh voucher.
  const pageHref = (target: number) => {
    const sp = new URLSearchParams();
    if (search) sp.set("q", search);
    if (target > 1) sp.set("page", String(target));
    const str = sp.toString();
    return `/admin/vouchers${str ? `?${str}` : ""}`;
  };

  async function toggleVoucher(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const current = formData.get("isActive") === "true";
    await prisma.voucher.update({ where: { id }, data: { isActive: !current } });
    revalidatePath("/admin/vouchers");
  }

  async function deleteVoucher(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const voucher = await prisma.voucher.findUnique({
      where: { id },
      select: { kind: true, userId: true, code: true },
    });
    if (voucher && isLoyaltyClaimVoucher(voucher)) {
      revalidatePath("/admin/vouchers");
      return;
    }
    await prisma.voucher.delete({ where: { id } });
    revalidatePath("/admin/vouchers");
  }

  const now = new Date();
  // Kartu statistik menghitung SELURUH tabel, bukan hanya halaman yang tampil.
  const counts = tallyVoucherCategories(
    loyaltyCount,
    nonLoyaltyGroups.map((g) => ({
      kind: g.kind,
      sourceType: g.sourceType,
      _count: g._count._all,
    })),
  );

  return (
    <AdminPage maxWidth="xl">
      <PageHeader
        title="Voucher"
        subtitle={
          search
            ? `${total} voucher cocok dengan "${search}".`
            : `${total} voucher total · kelola promo & loyalty reward`
        }
        actions={
          <Button href="/admin/vouchers/new" size="sm">
            + Buat voucher
          </Button>
        }
      />

      <section className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          label="Diskon Produk"
          value={counts.PRODUCT_DISCOUNT}
          helper="Voucher potongan produk"
          variant="primary"
        />
        <StatCard
          label="Gratis Ongkir"
          value={counts.FREE_SHIPPING}
          helper="Voucher free shipping"
          variant="success"
        />
        <StatCard
          label="Claim Loyalty"
          value={counts.LOYALTY_CLAIM}
          helper="Reward dari point"
          variant="accent"
        />
        <StatCard
          label="Manual / Private"
          value={counts.MANUAL_PRIVATE}
          helper="Seller-issued private"
          variant="warning"
        />
      </section>

      {/* Kotak cari — kode atau nama campaign. Wajib ada begitu daftarnya
          dipaginasi: tanpa ini, mencari satu voucher berarti menggulir
          halaman demi halaman. */}
      <form className="mt-5 flex gap-2 md:mt-8" method="GET" action="/admin/vouchers">
        <input
          type="search"
          name="q"
          defaultValue={search}
          aria-label="Cari kode atau nama voucher"
          placeholder="🔍 Cari kode / nama voucher..."
          className="min-w-0 flex-1 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-natalo-600"
        />
        <Button type="submit">Cari</Button>
        {search && (
          <Button href="/admin/vouchers" variant="secondary">
            Reset
          </Button>
        )}
      </form>

      <div className="mt-4 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
        {pageBeyondEnd ? (
          <EmptyState
            icon="📄"
            title={`Halaman ${page} tidak ada`}
            description={`Daftar ini hanya sampai halaman ${totalPages}. Mungkin ada voucher yang terhapus setelah tautannya dibuka.`}
            action={{ label: "Kembali ke halaman 1", href: pageHref(1) }}
            size="full"
          />
        ) : vouchers.length === 0 ? (
          <EmptyState
            icon={search ? "🔍" : "🎟️"}
            title={search ? `Tidak ada voucher cocok "${search}"` : "Belum ada voucher"}
            description={
              search
                ? "Coba kata kunci lain — pencarian mencakup kode dan nama voucher."
                : "Buat voucher pertama untuk mulai campaign promo atau loyalty reward."
            }
            action={
              search
                ? { label: "Reset pencarian", href: "/admin/vouchers" }
                : { label: "Buat voucher pertama", href: "/admin/vouchers/new" }
            }
            size="full"
          />
        ) : (
          <div className="divide-y divide-zinc-100">
            {vouchers.map((v) => {
              const expired = v.expiresAt && v.expiresAt < now;
              const maxed = v.maxUsage !== null && v.usedCount >= v.maxUsage;
              const statusOk = v.isActive && !expired && !maxed;

              const discountParts: string[] = [];
              if (v.discountPercent) discountParts.push(`${v.discountPercent}%`);
              if (v.discountAmount) discountParts.push(formatRupiah(v.discountAmount));
              const typeLabel =
                v.type === "PUBLIC_FREE_SHIPPING"
                  ? "Public Gratis Ongkir"
                  : v.type === "PUBLIC_PRODUCT_DISCOUNT"
                    ? "Public Diskon Produk"
                    : v.type === "LOYALTY_POINT_CLAIM"
                      ? "Loyalty Reward"
                      : "Private Manual";
              const kindLabel = voucherKindLabel(v.kind);
              const scopeLabel =
                v.discountScope === "SHIPPING" ? "Ongkir" : "Produk";

              return (
                <div key={v.id} className="flex flex-col gap-4 p-4 transition hover:bg-zinc-50/60 md:flex-row md:flex-wrap md:items-start md:justify-between md:p-5">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-mono text-base font-black text-zinc-950">{v.code}</span>
                      <Badge variant="info">{typeLabel}</Badge>
                      <Badge
                        variant={
                          statusOk
                            ? "success"
                            : expired
                              ? "neutral"
                              : maxed
                                ? "warning"
                                : "danger"
                        }
                      >
                        {statusOk
                          ? "Aktif"
                          : expired
                            ? "Kedaluwarsa"
                            : maxed
                              ? "Habis"
                              : "Nonaktif"}
                      </Badge>
                      <Badge variant="info">{kindLabel}</Badge>
                      {v.kind === "PRODUCT_DISCOUNT" && (
                        <Badge variant="purple">
                          Target: {voucherTargetUserLabel(v.targetUser)}
                        </Badge>
                      )}
                    </div>

                    {v.description && (
                      <p className="mt-1 text-sm text-zinc-500">{v.description}</p>
                    )}

                    <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-zinc-500">
                      <span>Scope: <strong className="text-zinc-700">{scopeLabel}</strong></span>
                      <span>Diskon: <strong className="text-zinc-700">{discountParts.join(" + ") || "-"}</strong></span>
                      {v.maxDiscountAmount !== null && (
                        <span>Maks. potongan: <strong className="text-zinc-700">{formatRupiah(v.maxDiscountAmount)}</strong></span>
                      )}
                      {v.minimumOrder > 0 && (
                        <span>Min. belanja: <strong className="text-zinc-700">{formatRupiah(v.minimumOrder)}</strong></span>
                      )}
                      {v.kind === "PRODUCT_DISCOUNT" && v.targetUser === "NEW_MEMBER" && (
                        <span>
                          Rule: <strong className="text-zinc-700">
                            ≤{v.newMemberMaxAccountAgeDays ?? "-"} hari
                            {v.newMemberRequireNoSuccessfulOrder ? " · belum checkout" : ""}
                          </strong>
                        </span>
                      )}
                      <span>Batas per user: <strong className="text-zinc-700">{voucherUsageLimitLabel(v)}</strong></span>
                      <span>
                        Digunakan: <strong className="text-zinc-700">{v.usedCount}
                        {v.maxUsage !== null ? `/${v.maxUsage}` : ""}</strong>
                      </span>
                      {v.eligibleUserIds.length > 0 && (
                        <span>Eligible user: <strong className="text-zinc-700">{v.eligibleUserIds.length}</strong></span>
                      )}
                      {v.eligibleProductIds.length > 0 && (
                        <span>Target produk: <strong className="text-zinc-700">{v.eligibleProductIds.length}</strong></span>
                      )}
                      {v.eligibleCategoryIds.length > 0 && (
                        <span>Target kategori: <strong className="text-zinc-700">{v.eligibleCategoryIds.length}</strong></span>
                      )}
                      {v.expiresAt && (
                        <span>
                          Berlaku s/d: <strong className="text-zinc-700">
                            {v.expiresAt.toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric" })}
                          </strong>
                        </span>
                      )}
                    </div>
                  </div>

                  <div className="flex flex-wrap items-center gap-2">
                    {/* Edit */}
                    <Button
                      href={`/admin/vouchers/${v.id}/edit`}
                      variant="secondary"
                      size="md"
                    >
                      ✏️ Edit
                    </Button>

                    {/* Toggle aktif/nonaktif */}
                    <form action={toggleVoucher}>
                      <input type="hidden" name="id" value={v.id} />
                      <input type="hidden" name="isActive" value={String(v.isActive)} />
                      <Button type="submit" variant="secondary" size="md">
                        {v.isActive ? "Nonaktifkan" : "Aktifkan"}
                      </Button>
                    </form>

                    {/* Hapus dengan konfirmasi */}
                    {isLoyaltyClaimVoucher(v) ? (
                      <span className="inline-flex min-h-11 items-center rounded-full border border-zinc-200 px-4 text-xs font-bold text-zinc-500">
                        Klaim user
                      </span>
                    ) : (
                      <form action={deleteVoucher}>
                        <input type="hidden" name="id" value={v.id} />
                        <ConfirmSubmitButton
                          className="inline-flex min-h-11 items-center justify-center rounded-full border border-red-200 bg-white px-5 text-sm font-bold text-red-600 transition hover:border-red-300 hover:bg-red-50"
                          message={
                            v.usedCount > 0
                              ? `⚠️ Voucher "${v.code}" sudah dipakai ${v.usedCount} kali. Order yang sudah pakai voucher ini tidak terpengaruh, tapi voucher akan hilang dari daftar. Lanjutkan hapus?`
                              : `Hapus voucher "${v.code}"? Tindakan ini tidak bisa dibatalkan.`
                          }
                        >
                          🗑️ Hapus
                        </ConfirmSubmitButton>
                      </form>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {totalPages > 1 && (
        <div className="mt-6 flex items-center justify-between gap-3">
          <p className="text-sm text-zinc-500">
            Halaman <span className="font-black text-zinc-950">{page}</span> dari{" "}
            <span className="font-black text-zinc-950">{totalPages}</span>
          </p>
          <div className="flex gap-2">
            {page > 1 && (
              <Button href={pageHref(page - 1)} variant="secondary" size="sm">
                ← Sebelumnya
              </Button>
            )}
            {page < totalPages && (
              <Button href={pageHref(page + 1)} size="sm">
                Berikutnya →
              </Button>
            )}
          </div>
        </div>
      )}
    </AdminPage>
  );
}
