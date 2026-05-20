/**
 * /admin/diskon/flash-sale/new — Form Flash Sale baru.
 *
 * Mekanisme: pilih 1 atau lebih produk → set harga flash (discountPrice)
 * + waktu berakhir (flashSaleEndsAt). Pakai field existing di Product
 * model (Opsi A — tidak buat model FlashSale baru).
 *
 * Server action update batch produk. Setelah save, produk akan muncul
 * di Flash Sale section di home customer dengan countdown timer
 * (sudah ke-handle di customer side existing).
 */
import Link from "next/link";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export default async function FlashSaleNewPage() {
  // Ambil daftar produk untuk multi-select. Filter hanya yang aktif
  // + tidak sedang di flash sale lain (flashSaleEndsAt null atau expired).
  const now = new Date();
  const products = await prisma.product.findMany({
    where: {
      isActive: true,
      OR: [
        { flashSaleEndsAt: null },
        { flashSaleEndsAt: { lt: now } },
      ],
    },
    orderBy: { name: "asc" },
    take: 200,
    select: {
      id: true,
      name: true,
      price: true,
      imageUrl: true,
      slug: true,
    },
  });

  async function createFlashSale(formData: FormData) {
    "use server";

    const productIds = formData.getAll("productIds").map(String).filter(Boolean);
    const discountPercent = parseInt(
      String(formData.get("discountPercent") || "0"),
      10,
    );
    const endsAtRaw = String(formData.get("endsAt") || "").trim();
    const endsAt = endsAtRaw ? new Date(endsAtRaw) : null;

    if (productIds.length === 0 || !endsAt || endsAt <= new Date()) return;
    if (discountPercent < 1 || discountPercent > 95) return;

    // Update batch — hitung discountPrice dari current price × (1 - %)
    // per produk supaya tetap akurat per-item.
    const productsToUpdate = await prisma.product.findMany({
      where: { id: { in: productIds } },
      select: { id: true, price: true },
    });

    await Promise.all(
      productsToUpdate.map((p) =>
        prisma.product.update({
          where: { id: p.id },
          data: {
            discountPrice: Math.round(p.price * (1 - discountPercent / 100)),
            flashSaleEndsAt: endsAt,
          },
        }),
      ),
    );

    redirect("/admin/diskon");
  }

  return (
    <div className="mx-auto max-w-4xl px-4 py-5 md:px-8 md:py-10">
      <Link
        href="/admin/diskon"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke Buat Diskon
      </Link>
      <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
        Buat Flash Sale
      </h1>
      <p className="mt-1 text-sm text-zinc-500">
        Pilih produk + diskon + waktu berakhir. Produk akan tampil di
        Flash Sale section dengan countdown timer.
      </p>

      <form action={createFlashSale} className="mt-6 space-y-5">
        {/* Periode + Diskon */}
        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-sm font-semibold text-zinc-700">
              <span className="mr-1 text-red-500">•</span>Diskon (%)
            </label>
            <input
              type="number"
              name="discountPercent"
              min={1}
              max={95}
              required
              placeholder="20"
              className="mt-1.5 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-600"
            />
            <p className="mt-1 text-xs text-zinc-500">
              ⓘ Antara 1–95%. Diterapkan ke semua produk yang dipilih.
            </p>
          </div>
          <div>
            <label className="block text-sm font-semibold text-zinc-700">
              <span className="mr-1 text-red-500">•</span>Berakhir
            </label>
            <input
              type="datetime-local"
              name="endsAt"
              required
              className="mt-1.5 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-600"
            />
            <p className="mt-1 text-xs text-zinc-500">
              ⓘ Harus waktu di masa depan. Promosi otomatis berakhir.
            </p>
          </div>
        </div>

        {/* Pilih produk (multi-checklist) */}
        <div>
          <label className="block text-sm font-semibold text-zinc-700">
            <span className="mr-1 text-red-500">•</span>Pilih Produk (
            {products.length} produk eligible)
          </label>
          <p className="mt-0.5 text-xs text-zinc-500">
            Hanya produk yang sedang tidak di Flash Sale yang muncul di
            sini.
          </p>
          <div className="mt-2 max-h-96 overflow-y-auto rounded-xl border border-zinc-200 bg-white">
            {products.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-zinc-400">
                Semua produk sedang di Flash Sale atau tidak ada produk
                aktif. Tunggu Flash Sale berakhir dulu.
              </p>
            ) : (
              <div className="divide-y divide-zinc-100">
                {products.map((p) => (
                  <label
                    key={p.id}
                    className="flex cursor-pointer items-center gap-3 px-4 py-2.5 hover:bg-zinc-50"
                  >
                    <input
                      type="checkbox"
                      name="productIds"
                      value={p.id}
                      className="h-4 w-4 rounded border-zinc-300"
                    />
                    {p.imageUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={p.imageUrl}
                        alt=""
                        className="h-10 w-10 rounded border border-zinc-200 object-cover"
                      />
                    ) : (
                      <div className="h-10 w-10 rounded border border-zinc-200 bg-zinc-100" />
                    )}
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-semibold text-zinc-900">
                        {p.name}
                      </p>
                      <p className="text-xs text-zinc-500">
                        Rp {p.price.toLocaleString("id-ID")}
                      </p>
                    </div>
                  </label>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Submit */}
        <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row">
          <Link
            href="/admin/diskon"
            className="rounded-full border border-zinc-300 px-6 py-3 text-center text-sm font-bold"
          >
            Batal
          </Link>
          <button
            type="submit"
            className="flex-1 rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white hover:bg-natalo-700 sm:flex-none"
          >
            Simpan Flash Sale
          </button>
        </div>
      </form>
    </div>
  );
}
