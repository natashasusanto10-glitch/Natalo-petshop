const fs = require("fs");
const { PrismaClient } = require("@prisma/client");

const prisma = new PrismaClient();

async function main() {
  const products = JSON.parse(fs.readFileSync("products_complete.json", "utf8"));
  const generated = products.filter(
    (product) => product.name_source === "ai_generated" && product.name
  );

  let updated = 0;

  for (const product of generated) {
    await prisma.product.update({
      where: { id: product.id },
      data: { name: product.name },
    });
    updated += 1;
  }

  console.log(`updated=${updated}`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
