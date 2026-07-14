/**
 * READ-ONLY diagnostic — investigasi notifikasi abandoned-cart yang salah.
 *
 * Tujuan: cari tahu apakah ada row CartItem "basi" (nyangkut di server)
 * yang memicu notifikasi padahal user sudah menghapusnya dari cart.
 *
 * TIDAK mengubah data apa pun — hanya SELECT/count.
 *
 * Cara jalan (butuh DATABASE_URL produksi ter-set di env):
 *   node scripts/diag-abandoned-cart.mjs "Woo Nature's Touch Pet Wet Wipes"
 *
 * Argumen 1 (opsional): potongan nama produk yang muncul di notifikasi.
 * Default: "Woo Nature's Touch Pet Wet Wipes".
 */
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const needle = process.argv[2] || "Woo Nature's Touch Pet Wet Wipes";

const FOUR_HOURS = 4 * 60 * 60 * 1000;
const SEVEN_DAYS = 7 * 24 * 60 * 60 * 1000;

function fmt(d) {
  return d ? new Date(d).toISOString() : "null";
}

async function main() {
  const now = Date.now();
  console.log(`\n=== Diagnostic abandoned-cart ===`);
  console.log(`Now: ${new Date(now).toISOString()}`);
  console.log(`Mencari CartItem dengan name mengandung: "${needle}"\n`);

  // 1. Semua row CartItem yang cocok dengan nama produk di notifikasi.
  const matches = await prisma.cartItem.findMany({
    where: { name: { contains: needle, mode: "insensitive" } },
    select: {
      id: true,
      userId: true,
      name: true,
      quantity: true,
      createdAt: true,
      updatedAt: true,
      notifiedAbandonedAt: true,
    },
    orderBy: { createdAt: "asc" },
  });

  console.log(`[1] Row CartItem cocok: ${matches.length}`);
  for (const m of matches) {
    const ageMs = now - new Date(m.createdAt).getTime();
    const ageH = (ageMs / 3_600_000).toFixed(1);
    const eligibleNow =
      m.notifiedAbandonedAt === null &&
      ageMs >= FOUR_HOURS &&
      ageMs <= SEVEN_DAYS;
    console.log(
      `    - user=${m.userId} qty=${m.quantity} umur=${ageH}h ` +
        `created=${fmt(m.createdAt)} updated=${fmt(m.updatedAt)} ` +
        `notified=${fmt(m.notifiedAbandonedAt)} ` +
        `eligibleSekarang=${eligibleNow}`,
    );
  }

  if (matches.length === 0) {
    console.log(
      `\n    → Tidak ada row tersisa sekarang. Kalau notif tetap terkirim ` +
        `sebelumnya, kemungkinan row sudah dihapus SETELAH cron jalan ` +
        `(mendukung skenario timing / sync telat), atau row memang basi ` +
        `lalu ke-clear belakangan.`,
    );
  }

  // 2. Untuk tiap user yang punya row cocok, tampilkan SELURUH isi cart-nya
  //    sekarang — untuk bandingkan dengan yang user lihat di app.
  const userIds = [...new Set(matches.map((m) => m.userId))];
  for (const uid of userIds) {
    const full = await prisma.cartItem.findMany({
      where: { userId: uid },
      select: { name: true, quantity: true, createdAt: true, updatedAt: true },
      orderBy: { updatedAt: "desc" },
    });
    console.log(`\n[2] Cart server user=${uid} — ${full.length} item:`);
    for (const it of full) {
      console.log(
        `    - ${it.name} x${it.quantity} ` +
          `(created=${fmt(it.createdAt)}, updated=${fmt(it.updatedAt)})`,
      );
    }
  }

  // 3. Statistik global: berapa banyak row "basi" yang berpotensi jadi
  //    sinyal abandoned palsu (belum notified, umur 4h-7d).
  const eligibleCount = await prisma.cartItem.count({
    where: {
      notifiedAbandonedAt: null,
      createdAt: {
        gte: new Date(now - SEVEN_DAYS),
        lte: new Date(now - FOUR_HOURS),
      },
    },
  });
  console.log(
    `\n[3] Total CartItem eligible abandoned-cart SEKARANG (semua user): ${eligibleCount}`,
  );
  console.log(`\n=== Selesai (tidak ada data yang diubah) ===\n`);
}

main()
  .catch((e) => {
    console.error("Diagnostic error:", e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
