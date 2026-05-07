import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
await prisma.orderItem.deleteMany();
await prisma.order.deleteMany();
await prisma.product.deleteMany();
await prisma.category.deleteMany();
  const category = await prisma.category.upsert({
    where: { slug: "produk-unggulan" },
    update: {},
    create: { name: "Produk Unggulan", slug: "produk-unggulan" },
  });

  const products = [
  {
    name: "Angels Creamy Chicken 15gr x 10pcs",
    slug: "angels-creamy-chicken-15gr-x-10pcs",
    description: `Snack creamy untuk kucing dengan rasa chicken. Cocok untuk reward, camilan harian, atau campuran makanan.`,
    price: 1000,
    stock: 1000,
    weightGram: 20,
    imageUrl: "/products/angels-creamy-chicken.png",
  },
  {
    name: "Angels Creamy Tuna 15gr x 10pcs",
    slug: "angels-creamy-tuna-15gr-x-10pcs",
    description: `Kejutan kecil yang menghadirkan kenyamanan dan bahagia. Angels Snack Kucing 15 GR berbentuk strip yang creamy.`,
    price: 1000,
    stock: 1000,
    weightGram: 20,
    imageUrl: "/products/angels-creamy-tuna.png",
  },
  {
    name: "Angels Creamy Salmon 15gr x 10pcs",
    slug: "angels-creamy-salmon-15gr-x-10pcs",
    description: `Snack creamy untuk kucing dengan rasa salmon. Cocok untuk reward, camilan harian, atau campuran makanan.

Keunggulan Utama:
- Tekstur creamy dan mudah disukai kucing.
- Praktis untuk camilan harian.
- Cocok untuk kitten dan adult.
- Bisa diberikan langsung atau dicampur dengan makanan utama.`,
    price: 1000,
    stock: 1000,
    weightGram: 20,
    imageUrl: "/products/angels-creamy-salmon.jpg",
  },
];

  for (const product of products) {
    await prisma.product.upsert({
      where: { slug: product.slug },
      update: product,
      create: { ...product, categoryId: category.id },
    });
  }

  await prisma.voucher.upsert({
    where: { code: "MEMBER10" },
    update: {},
    create: {
      code: "MEMBER10",
      description: "Diskon 10% untuk pembelian pertama member.",
      discountPercent: 10,
      minimumOrder: 50000,
    },
  });
}

main()
  .then(async () => prisma.$disconnect())
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
