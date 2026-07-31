/**
 * Seed akun demo untuk review Google Play / App Store.
 *
 * Membuat (idempoten — aman dijalankan ulang):
 *   - User demo.review@natalopetshop.com (CUSTOMER, password bcrypt)
 *   - 1 Address utama
 *   - 1 Pet (Anabulku)
 *   - 1 Order status DELIVERED + item + timeline (halaman Transaksi terisi)
 *   - 1 FeedPost PHOTO_CAROUSEL status ACTIVE (feed terlihat aktif)
 *   - RefundWallet (saldo 0, biar menu saldo tidak error)
 *
 * ⚠️ Akun ini PERMANEN — jangan dihapus setelah lolos review.
 *
 * Password TIDAK disimpan di repo — wajib lewat env:
 *   DEMO_REVIEW_PASSWORD='...' node scripts/seed-demo-review-account.mjs
 */
import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

const EMAIL = "demo.review@natalopetshop.com";
const PASSWORD = process.env.DEMO_REVIEW_PASSWORD;
if (!PASSWORD) {
  console.error(
    "DEMO_REVIEW_PASSWORD belum di-set. Contoh:\n" +
      "  DEMO_REVIEW_PASSWORD='...' node scripts/seed-demo-review-account.mjs"
  );
  process.exit(1);
}
const PHONE = "6281200000099";
const NAME = "Demo Review";
const USERNAME = "demo.review";

async function main() {
  const passwordHash = await bcrypt.hash(PASSWORD, 10);

  // ── User ────────────────────────────────────────────────────────────
  const user = await prisma.user.upsert({
    where: { email: EMAIL },
    update: { passwordHash, name: NAME, role: "CUSTOMER" },
    create: {
      email: EMAIL,
      passwordHash,
      name: NAME,
      phone: PHONE,
      username: USERNAME,
      usernameUpdatedAt: new Date(),
      role: "CUSTOMER",
      bio: "Akun demo untuk review aplikasi.",
    },
  });
  console.log("user:", user.id, user.email);

  // ── Refund wallet ───────────────────────────────────────────────────
  await prisma.refundWallet.upsert({
    where: { userId: user.id },
    update: {},
    create: { userId: user.id, availableBalance: 0 },
  });

  // ── Alamat ──────────────────────────────────────────────────────────
  const existingAddress = await prisma.address.findFirst({
    where: { userId: user.id },
  });
  if (!existingAddress) {
    await prisma.address.create({
      data: {
        userId: user.id,
        label: "Rumah",
        recipient: NAME,
        phone: PHONE,
        address: "Jl. Contoh Demo No. 1, Kelurahan Demo",
        city: "Jakarta Selatan",
        cityName: "Jakarta Selatan",
        provinceName: "DKI Jakarta",
        districtName: "Kebayoran Baru",
        postalCode: "12190",
        isMain: true,
      },
    });
    console.log("address: created");
  } else {
    console.log("address: sudah ada");
  }

  // ── Pet ─────────────────────────────────────────────────────────────
  const existingPet = await prisma.pet.findFirst({ where: { userId: user.id } });
  if (!existingPet) {
    await prisma.pet.create({
      data: {
        userId: user.id,
        name: "Miko",
        type: "Kucing",
        breed: "Domestik",
        gender: "male",
        bio: "Anabul demo untuk keperluan review aplikasi.",
        birthDate: new Date("2023-05-10"),
        weightKg: 4.2,
      },
    });
    console.log("pet: created");
  } else {
    console.log("pet: sudah ada");
  }

  // ── Produk sumber (produk aktif termurah yang punya foto) ───────────
  const product = await prisma.product.findFirst({
    where: {
      isActive: true,
      creationState: "ready",
      imageUrl: { not: null },
      price: { gt: 0 },
    },
    orderBy: { price: "asc" },
  });
  if (!product) throw new Error("Tidak ada produk aktif dengan foto di DB.");
  console.log("produk demo:", product.name, product.price);

  // ── Order DELIVERED ─────────────────────────────────────────────────
  const ORDER_NUMBER = "DEMO-REVIEW-0001";
  let order = await prisma.order.findUnique({
    where: { orderNumber: ORDER_NUMBER },
  });
  if (!order) {
    const qty = 1;
    const subtotal = product.price * qty;
    const shippingCost = 15000;
    const now = new Date();
    const paidAt = new Date(now.getTime() - 6 * 24 * 3600 * 1000);
    const shippedAt = new Date(now.getTime() - 4 * 24 * 3600 * 1000);
    const deliveredAt = new Date(now.getTime() - 2 * 24 * 3600 * 1000);

    order = await prisma.order.create({
      data: {
        orderNumber: ORDER_NUMBER,
        userId: user.id,
        customerName: NAME,
        customerPhone: PHONE,
        customerEmail: EMAIL,
        shippingAddress: "Jl. Contoh Demo No. 1, Kebayoran Baru, Jakarta Selatan 12190",
        shippingCity: "Jakarta Selatan",
        shippingPostalCode: "12190",
        shippingProvinceName: "DKI Jakarta",
        shippingDistrictName: "Kebayoran Baru",
        orderType: "DELIVERY",
        shippingMethod: "DELIVERY",
        courierCode: "jne",
        courierService: "REG",
        trackingNumber: "DEMOREVIEW123456",
        subtotal,
        shippingCost,
        total: subtotal + shippingCost,
        status: "DELIVERED",
        paymentProvider: "MANUAL",
        paymentStatus: "PAID",
        paymentProofStatus: "VERIFIED",
        notes: "Pesanan contoh untuk review aplikasi (akun demo).",
        shippedAt,
        createdAt: paidAt,
        items: {
          create: [
            {
              productId: product.id,
              name: product.name,
              price: product.price,
              quantity: qty,
              weightGram: product.weightGram ?? 500,
            },
          ],
        },
        timelineEvents: {
          create: [
            { status: "PENDING", occurredAt: paidAt },
            { status: "PAID", occurredAt: paidAt },
            { status: "PROCESSING", occurredAt: new Date(paidAt.getTime() + 3600 * 1000) },
            { status: "SHIPPED", occurredAt: shippedAt },
            { status: "DELIVERED", occurredAt: deliveredAt },
          ],
        },
      },
    });
    console.log("order: created", order.orderNumber);
  } else {
    console.log("order: sudah ada", order.orderNumber);
  }

  // ── Feed post (foto) ────────────────────────────────────────────────
  const existingPost = await prisma.feedPost.findFirst({
    where: { authorId: user.id, deletedAt: null },
  });
  if (!existingPost) {
    const post = await prisma.feedPost.create({
      data: {
        authorId: user.id,
        authorRole: "CUSTOMER",
        kind: "PHOTO_CAROUSEL",
        tab: "KOMUNITAS",
        status: "ACTIVE",
        title: "Miko suka banget sama produk ini",
        description: "Postingan contoh dari akun demo untuk review aplikasi.",
        productId: product.id,
        publishedAt: new Date(),
        media: {
          create: [
            {
              mediaType: "image",
              url: product.imageUrl,
              altText: product.name,
              sortOrder: 0,
            },
          ],
        },
        taggedProducts: {
          create: [{ productId: product.id, position: 0 }],
        },
      },
    });
    console.log("feed post: created", post.id);
  } else {
    console.log("feed post: sudah ada", existingPost.id);
  }

  console.log("\n=== AKUN DEMO SIAP ===");
  console.log("Email   :", EMAIL);
  console.log("Password: (dari env DEMO_REVIEW_PASSWORD)");
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
