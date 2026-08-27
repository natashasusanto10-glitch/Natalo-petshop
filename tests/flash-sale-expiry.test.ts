import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { expiredFlashSaleWhere } from "../lib/product/flash-sale-expiry";
import { resolveActiveDiscount } from "../lib/product-pricing";

const NOW = new Date("2026-08-27T10:00:00.000Z");

/**
 * `expiredFlashSaleWhere` adalah klausa Prisma, tidak bisa dijalankan
 * tanpa DB. Yang diuji di sini bentuknya — dan yang lebih penting,
 * KESELARASANNYA dengan `resolveActiveDiscount`: klausa ini harus
 * mencocokkan tepat produk yang oleh sisi pelanggan sudah dianggap
 * tidak berdiskon. Kalau dua aturan itu berbeda, cron akan menghapus
 * harga promo yang masih berjalan.
 */
describe("expiredFlashSaleWhere", () => {
  it("hanya menyentuh baris yang masih punya discountPrice", () => {
    const where = expiredFlashSaleWhere(NOW);
    assert.deepEqual(where.discountPrice, { not: null });
  });

  it("mencakup dua bentuk sisa: tanpa tanggal, dan tanggal sudah lewat", () => {
    const where = expiredFlashSaleWhere(NOW);
    assert.deepEqual(where.OR, [
      { flashSaleEndsAt: null },
      { flashSaleEndsAt: { lte: NOW } },
    ]);
  });

  it("selaras dengan resolveActiveDiscount — Flash Sale aktif TIDAK boleh cocok", () => {
    const besok = new Date(NOW.getTime() + 24 * 60 * 60 * 1000);
    // Kalau pelanggan masih melihat diskonnya, cron tidak boleh menghapusnya.
    const masihAktif = resolveActiveDiscount(
      100_000,
      { discountPrice: 70_000, endsAt: besok },
      [],
      NOW,
    );
    assert.ok(masihAktif, "prasyarat: promo ini memang masih aktif");

    const { OR } = expiredFlashSaleWhere(NOW);
    // besok > NOW, jadi tidak lolos `lte: NOW`, dan endsAt-nya tidak null.
    assert.ok(besok > (OR![1] as { flashSaleEndsAt: { lte: Date } }).flashSaleEndsAt.lte);
  });

  it("selaras dengan resolveActiveDiscount — yang sudah lewat memang sudah mati", () => {
    const kemarin = new Date(NOW.getTime() - 24 * 60 * 60 * 1000);
    const sudahMati = resolveActiveDiscount(
      131_500,
      { discountPrice: 78_900, endsAt: kemarin },
      [],
      NOW,
    );
    // Persis kondisi 11 produk sisa yang ditemukan di produksi:
    // discountPrice masih terisi, tapi pelanggan tidak melihat diskon apa pun.
    assert.equal(sudahMati, null);
  });

  it("tanggal PERSIS sekarang dianggap sudah berakhir — sama dengan pelanggan", () => {
    // resolveActiveDiscount memakai `endsAt > now` (bukan >=), jadi promo
    // yang berakhir tepat detik ini sudah tidak berlaku. Klausa cron pakai
    // `lte` supaya cocok persis, bukan `lt` yang akan meninggalkannya.
    assert.equal(
      resolveActiveDiscount(100_000, { discountPrice: 50_000, endsAt: NOW }, [], NOW),
      null,
    );
    const { OR } = expiredFlashSaleWhere(NOW);
    assert.deepEqual(OR![1], { flashSaleEndsAt: { lte: NOW } });
  });
});
