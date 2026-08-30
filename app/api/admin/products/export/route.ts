import ExcelJS from "exceljs";
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  EXPORT_COLUMNS,
  buildExportRows,
  type ExportProduct,
} from "@/lib/admin/product-export";

export const dynamic = "force-dynamic";
// Katalog ~1.4rb produk + varian: query + tulis xlsx masih jauh di bawah
// batas, tapi jangan biarkan default 10s memotong kalau katalog membesar.
export const maxDuration = 30;

/**
 * GET /api/admin/products/export
 *
 * Unduh seluruh katalog sebagai .xlsx gaya Shopee Seller Centre — satu
 * baris per varian. Dipanggil lewat <a href> dari halaman admin produk,
 * jadi auth memakai cookie sesi yang sama seperti navigasi biasa.
 */
export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const products = await prisma.product.findMany({
    orderBy: { name: "asc" },
    select: {
      name: true,
      slug: true,
      sku: true,
      price: true,
      discountPrice: true,
      memberPrice: true,
      flashSaleEndsAt: true,
      stock: true,
      weightGram: true,
      isActive: true,
      hasVariants: true,
      brand: { select: { name: true } },
      category: { select: { name: true } },
      variants: {
        where: { deletedAt: null },
        orderBy: { createdAt: "asc" },
        select: {
          sku: true,
          price: true,
          stock: true,
          weightGram: true,
          isActive: true,
          options: {
            select: {
              option: {
                select: {
                  value: true,
                  attribute: { select: { name: true, position: true } },
                },
              },
            },
          },
        },
      },
    },
  });

  const exportProducts: ExportProduct[] = products.map((p) => ({
    name: p.name,
    slug: p.slug,
    sku: p.sku,
    brandName: p.brand?.name ?? null,
    categoryName: p.category?.name ?? null,
    price: p.price,
    discountPrice: p.discountPrice,
    memberPrice: p.memberPrice,
    flashSaleEndsAt: p.flashSaleEndsAt,
    stock: p.stock,
    weightGram: p.weightGram,
    isActive: p.isActive,
    hasVariants: p.hasVariants,
    variants: p.variants.map((v) => ({
      sku: v.sku,
      price: v.price,
      stock: v.stock,
      weightGram: v.weightGram,
      isActive: v.isActive,
      options: v.options.map((o) => ({
        value: o.option.value,
        attributeName: o.option.attribute.name,
        attributePosition: o.option.attribute.position,
      })),
    })),
  }));

  const rows = buildExportRows(exportProducts);

  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("Produk");
  sheet.columns = EXPORT_COLUMNS;
  sheet.getRow(1).font = { bold: true };
  // Header lengket + filter — kebiasaan dari ekspor Seller Centre yang
  // membuat lembarnya langsung enak dipakai opname tanpa dirapikan dulu.
  sheet.views = [{ state: "frozen", ySplit: 1 }];
  sheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: EXPORT_COLUMNS.length },
  };
  for (const row of rows) sheet.addRow(row);

  const buffer = await workbook.xlsx.writeBuffer();
  const tanggal = new Date().toISOString().slice(0, 10);
  return new NextResponse(Buffer.from(buffer), {
    headers: {
      "Content-Type":
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="natalo-produk-${tanggal}.xlsx"`,
      "Cache-Control": "no-store",
    },
  });
}
