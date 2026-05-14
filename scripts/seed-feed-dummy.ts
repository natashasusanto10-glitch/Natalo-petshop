/**
 * Seed dummy feed posts untuk testing F3 UI end-to-end.
 *
 * Usage: npx dotenv -e .env.local -- npx tsx scripts/seed-feed-dummy.ts
 *
 * Idempotent — clear existing dummy lalu insert 5 sample (mix kind + tab).
 * Pakai admin user existing (id="admin"). Video URL pakai public sample
 * MP4 dari Google's storyblok demo (kalau access denied, ganti ke URL
 * video kamu sendiri).
 */
import { prisma } from "@/lib/prisma";

// Sample public video (640x360, MP4 H.264) — Google storage demo.
const SAMPLE_VIDEO =
  "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4";
const SAMPLE_THUMB =
  "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg";

async function main() {
  // Ensure admin user ada
  const admin = await prisma.user.upsert({
    where: { id: "admin" },
    create: { id: "admin", name: "Admin Natalo", role: "ADMIN" },
    update: {},
  });

  // Clear dummy posts dgn marker di title
  await prisma.feedPost.deleteMany({
    where: { title: { startsWith: "[DUMMY]" } },
  });

  // Pick 1 produk existing untuk tag
  const someProduct = await prisma.product.findFirst({
    where: { isActive: true },
    orderBy: { createdAt: "desc" },
    select: { id: true, name: true, price: true },
  });

  const now = new Date();

  const created: Array<{ kind: string; title: string }> = [];

  // 1. VIDEO_ONLY (admin edukasi)
  const p1 = await prisma.feedPost.create({
    data: {
      authorId: admin.id,
      authorRole: "ADMIN",
      kind: "VIDEO_ONLY",
      tab: "REKOMENDASI",
      status: "ACTIVE",
      title: "[DUMMY] Tips Memilih Makanan Kucing yang Tepat",
      description:
        "Pilih makanan berdasarkan usia, berat, dan kondisi kesehatan. Pastikan ada protein hewani sebagai bahan utama.",
      videoUrl: SAMPLE_VIDEO,
      thumbnailUrl: SAMPLE_THUMB,
      videoDurationSec: 596,
      videoWidth: 640,
      videoHeight: 360,
      publishedAt: now,
    },
  });
  created.push({ kind: p1.kind, title: p1.title });

  // 2. VIDEO_PRODUCT (admin jualan)
  if (someProduct) {
    const p2 = await prisma.feedPost.create({
      data: {
        authorId: admin.id,
        authorRole: "ADMIN",
        kind: "VIDEO_PRODUCT",
        tab: "REKOMENDASI",
        status: "ACTIVE",
        title: `[DUMMY] Review ${someProduct.name}`,
        description: "Produk favorit pelanggan Natalo. Stok terbatas!",
        videoUrl: SAMPLE_VIDEO,
        thumbnailUrl: SAMPLE_THUMB,
        videoDurationSec: 596,
        videoWidth: 640,
        videoHeight: 360,
        productId: someProduct.id,
        publishedAt: now,
      },
    });
    created.push({ kind: p2.kind, title: p2.title });
  }

  // 3. PROMO (admin diskon)
  if (someProduct) {
    const p3 = await prisma.feedPost.create({
      data: {
        authorId: admin.id,
        authorRole: "ADMIN",
        kind: "PROMO",
        tab: "PROMO",
        status: "ACTIVE",
        title: `[DUMMY] Promo Spesial: ${someProduct.name}`,
        description: "Diskon spesial weekend ini. Hemat sampai 20%!",
        videoUrl: SAMPLE_VIDEO,
        thumbnailUrl: SAMPLE_THUMB,
        videoDurationSec: 596,
        videoWidth: 640,
        videoHeight: 360,
        productId: someProduct.id,
        promoOriginalPrice: someProduct.price,
        promoDiscountPrice: Math.floor(someProduct.price * 0.8),
        promoStartsAt: now,
        promoEndsAt: new Date(now.getTime() + 7 * 24 * 3600 * 1000),
        publishedAt: now,
      },
    });
    created.push({ kind: p3.kind, title: p3.title });
  }

  // 4. PRODUCT_ONLY (admin card produk tanpa video)
  if (someProduct) {
    const p4 = await prisma.feedPost.create({
      data: {
        authorId: admin.id,
        authorRole: "ADMIN",
        kind: "PRODUCT_ONLY",
        tab: "REKOMENDASI",
        status: "ACTIVE",
        title: `[DUMMY] Rekomendasi: ${someProduct.name}`,
        description: "Best seller minggu ini.",
        productId: someProduct.id,
        publishedAt: now,
      },
    });
    created.push({ kind: p4.kind, title: p4.title });
  }

  console.log(`Seeded ${created.length} dummy feed posts:`);
  for (const c of created) console.log(`  - [${c.kind}] ${c.title}`);
}

main()
  .catch((err) => {
    console.error("Seed failed:", err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
