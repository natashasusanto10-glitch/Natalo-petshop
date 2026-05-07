const fs = require("fs");
const { PrismaClient } = require("@prisma/client");

const prisma = new PrismaClient();

async function main() {
  const products = await prisma.product.findMany({
    where: { isActive: true },
    orderBy: { createdAt: "desc" },
    include: { brand: true, category: true },
  });

  const data = products.map((product) => ({
    id: product.id,
    name: product.name,
    category: product.category?.name || "",
    brand: product.brand?.name || "",
    slug: product.slug,
    description: product.description,
    price: product.price,
    discountPrice: product.discountPrice,
    stock: product.stock,
    weightGram: product.weightGram,
    imageUrl: product.imageUrl,
    isActive: product.isActive,
  }));

  fs.writeFileSync("products_final.json", JSON.stringify(data, null, 2), "utf8");
  console.log(`exported=${data.length}`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
