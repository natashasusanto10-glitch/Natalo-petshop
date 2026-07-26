import { after, NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { syncProduct, productSearchWhere } from "@/lib/search";
import { putVariantsPayloadSchema } from "@/lib/validators/variant-schema";
import { createProductSchema, formatProductFieldErrors } from "@/lib/validators/product-schema";
import { Prisma } from "@prisma/client";
import { normalizeProductFormPayload } from "@/lib/product/admin-product-form";
import { validateCareFields } from "@/lib/product-dosage";

const MAX_LIMIT = 100;
const DEFAULT_LIMIT = 50;

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const sp = request.nextUrl.searchParams;
  const page = Math.max(1, parseInt(sp.get("page") || "1", 10));
  const limit = Math.min(
    MAX_LIMIT,
    Math.max(1, parseInt(sp.get("limit") || String(DEFAULT_LIMIT), 10))
  );
  const q = sp.get("q")?.trim() ?? "";
  const categorySlug = sp.get("category")?.trim() ?? "";

  // This endpoint is used only for feed-post product tagging, so only
  // active + in-stock products are taggable — including variant products
  // that have at least one active, in-stock variant.
  //
  // Search memakai productSearchWhere (fungsi yang sama dengan jalur DB
  // search storefront/app): tokenisasi query lalu cocokkan tiap token ke
  // nama + brand + SKU/opsi varian (AND antar-token, OR antar-field). Jauh
  // lebih baik dari `name contains q` yang lama — multi-kata, urutan bebas,
  // dan bisa cari by brand. Di-AND dengan filter tagging (aktif + ada stok).
  const searchWhere = q ? productSearchWhere(q) : undefined;
  const where: Prisma.ProductWhereInput = {
    isActive: true,
    AND: [
      {
        OR: [
          { hasVariants: false, stock: { gt: 0 } },
          { hasVariants: true, variants: { some: { isActive: true, stock: { gt: 0 } } } },
        ],
      },
      ...(searchWhere ? [searchWhere] : []),
    ],
  };
  if (categorySlug) where.category = { slug: categorySlug };

  const [products, total] = await Promise.all([
    prisma.product.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * limit,
      take: limit,
      select: {
        id: true,
        name: true,
        price: true,
        stock: true,
        imageUrl: true,
        category: { select: { name: true } },
      },
    }),
    prisma.product.count({ where }),
  ]);

  return NextResponse.json({
    products: products.map((p) => ({
      id: p.id,
      name: p.name,
      price: p.price,
      stock: p.stock,
      imageUrl: p.imageUrl,
      category: p.category?.name ?? "",
    })),
    total,
  });
}

/**
 * POST /api/admin/products
 *
 * Buat produk baru. Dipakai oleh flutter_admin "Tambah Produk Baru" form.
 *
 * Body: {name, price, stock, description?, imageUrl?, weightGram?,
 *        categoryId?, brandId?, isActive?}
 *
 * Auto-generate `slug` dari nama (slugify). Kalau slug tabrakan, append
 * suffix random 4 char.
 */
export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const parsed = createProductSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    const flat = parsed.error.flatten();
    return NextResponse.json(
      {
        // `error` WAJIB menyebut field pelakunya, bukan "Payload tidak valid".
        // Klien (ProductForm.tsx + flutter_admin) menampilkan `error` apa
        // adanya, jadi pesan buta di sini bikin admin tidak bisa menebak
        // field mana yang salah dari belasan kemungkinan.
        error: formatProductFieldErrors(flat.fieldErrors, flat.formErrors),
        fields: flat.fieldErrors,
      },
      { status: 400 },
    );
  }
  const body = parsed.data;
  let normalized;
  try {
    normalized = normalizeProductFormPayload({
      ...body,
      imageUrls: body.imageUrls ?? [body.imageUrl ?? "", ...body.gallery],
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Payload tidak valid" }, { status: 400 });
  }

  // Kalau hasVariants=true, validate attributes + variants pakai schema
  // yang sama dengan PUT variants endpoint. Kalau false, skip.
  if (body.hasVariants) {
    const variantParsed = putVariantsPayloadSchema.safeParse({
      hasVariants: body.hasVariants,
      attributes: body.attributes,
      variants: body.variants,
    });
    if (!variantParsed.success) {
      // Build issues[] dengan FULL PATH (mis. variants.1.sku) supaya
      // client bisa show detail per-error. `flatten().fieldErrors` cuma
      // capture top-level (variants, attributes) → nested errors dari
      // superRefine custom paths jadi hilang.
      const issues = variantParsed.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      }));
      return NextResponse.json(
        {
          // Sebut masalah pertama di `error` juga — klien lama yang cuma baca
          // `error` (tanpa render `issues`) tetap dapat petunjuk konkret.
          error: issues.length > 0
            ? `Varian tidak valid — ${issues[0].path}: ${issues[0].message}`
            : "Data varian tidak valid.",
          issues,
          fields: variantParsed.error.flatten().fieldErrors,
        },
        { status: 422 },
      );
    }
  }

  const careFields = validateCareFields(body as unknown as Record<string, unknown>);
  if (!careFields.ok) {
    return NextResponse.json({ error: careFields.error }, { status: 400 });
  }

  // Slugify nama → lowercase, hyphen, alphanumeric only.
  const baseSlug = body.name
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);

  // Cek konflik slug, append random 4 char kalau tabrakan.
  let slug = baseSlug;
  const existing = await prisma.product.findUnique({ where: { slug } });
  if (existing) {
    const suffix = Math.random().toString(36).slice(2, 6);
    slug = `${baseSlug}-${suffix}`;
  }

  // Atomic create — product + variants dalam satu transaction supaya
  // kalau varian gagal di-create, product juga di-rollback (no orphan).
  const hasVideo = Boolean(normalized.video?.guid || normalized.video?.url || normalized.video?.status);
  let created;
  try {
  created = await prisma.$transaction(async (tx) => {
    // Validasi SKU Induk unik kalau ada (Product.sku @unique). NULL kalau
    // varian aktif atau kosong — admin tidak isi SKU Induk untuk produk
    // multi-varian (pakai SKU per-varian saja).
    const trimmedSku = body.sku?.trim();
    const productSku = body.hasVariants ? null : trimmedSku || null;
    if (productSku) {
      const existingSku = await tx.product.findFirst({
        where: { sku: productSku },
      });
      if (existingSku) {
        throw new Error(`SKU Induk "${productSku}" sudah digunakan oleh produk lain.`);
      }
    }

    const product = await tx.product.create({
      data: {
        name: normalized.name,
        slug,
        sku: productSku,
        description: normalized.description,
        price: Math.round(body.price),
        stock: Math.round(body.stock),
        weightGram: Math.round(body.weightGram),
        imageUrl: normalized.imageUrl,
        gallery: normalized.gallery,
        categoryId: normalized.categoryId,
        brandId: normalized.brandId,
        isActive: hasVideo ? false : body.isActive,
        creationState: hasVideo ? "creating" : "ready",
        videoGuid: normalized.video?.guid ?? null,
        videoUrl: normalized.video?.url ?? null,
        videoStatus: normalized.video?.status ?? null,
        hasVariants: body.hasVariants,
        careCategory: careFields.careCategory,
        targetSpecies: careFields.targetSpecies,
        dosageRules: careFields.dosageRules === null ? Prisma.JsonNull : (careFields.dosageRules as unknown as Prisma.InputJsonValue),
        // Produk baru dianggap "baru disentuh admin" → tampil di atas admin list.
        lastEditedAt: new Date(),
      },
      select: {
        id: true,
        name: true,
        slug: true,
        price: true,
        stock: true,
        imageUrl: true,
      },
    });

    // Skip variant creation kalau hasVariants=false.
    if (!body.hasVariants) return product;

    // Build attributes + options. Map "attrPosition:optionValue" → DB id.
    type AttrPayload = {
      name: string;
      position: number;
      options: Array<{ value: string; position: number }>;
    };
    type VariantPayload = {
      optionRefs: string[];
      price: number;
      stock: number;
      weightGram: number;
      sku?: string;
      imageUrl?: string;
      isActive: boolean;
    };

    const attributes = body.attributes as AttrPayload[];
    const variants = body.variants as VariantPayload[];
    const optionRefMap = new Map<string, string>();

    for (const attr of attributes) {
      const createdAttr = await tx.variantAttribute.create({
        data: {
          productId: product.id,
          name: attr.name,
          position: attr.position,
          options: {
            create: attr.options.map((opt) => ({
              value: opt.value,
              position: opt.position,
            })),
          },
        },
        include: { options: true },
      });
      for (const opt of createdAttr.options) {
        optionRefMap.set(`${attr.position}:${opt.value}`, opt.id);
      }
    }

    for (const v of variants) {
      const optionIds = v.optionRefs
        .map((ref) => optionRefMap.get(ref))
        .filter((id): id is string => !!id);
      if (optionIds.length !== v.optionRefs.length) continue;

      if (v.sku) {
        const existingSku = await tx.productVariant.findFirst({
          where: { sku: v.sku },
        });
        if (existingSku) {
          throw new Error(`SKU "${v.sku}" sudah digunakan oleh varian lain.`);
        }
      }

      await tx.productVariant.create({
        data: {
          productId: product.id,
          sku: v.sku || null,
          price: v.price,
          stock: v.stock,
          weightGram: v.weightGram,
          imageUrl: v.imageUrl || null,
          isActive: v.isActive,
          options: {
            create: optionIds.map((optionId) => ({ optionId })),
          },
        },
      });
    }

    // Sync aggregate field di Product dari varian aktif:
    // - price = harga TERMURAH varian aktif
    // - stock = TOTAL stok semua varian aktif
    // - weightGram = berat varian termurah (representasi default)
    const activeVariants = await tx.productVariant.findMany({
      where: { productId: product.id, deletedAt: null, isActive: true },
      select: { price: true, stock: true, weightGram: true },
    });
    if (activeVariants.length > 0) {
      const prices = activeVariants.map((v) => v.price);
      const minPrice = Math.min(...prices);
      const cheapest = activeVariants.find((v) => v.price === minPrice)!;
      const totalStock = activeVariants.reduce((s, v) => s + v.stock, 0);
      const updated = await tx.product.update({
        where: { id: product.id },
        data: {
          price: minPrice,
          stock: totalStock,
          weightGram: cheapest.weightGram,
        },
        select: {
          id: true,
          name: true,
          slug: true,
          price: true,
          stock: true,
          imageUrl: true,
        },
      });
      return updated;
    }

    return product;
  });
  } catch (error) {
    // TANPA try/catch ini, throw di dalam transaction (mis. "SKU sudah
    // digunakan oleh varian lain", atau constraint Prisma) jadi unhandled
    // exception → Next.js balas 500 non-JSON → klien dapat `{}` → tampil
    // "Gagal menyimpan produk." tanpa sebab. Padahal pesannya sudah spesifik.
    console.error("[POST /api/admin/products] gagal create produk", error);
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
      const target = Array.isArray(error.meta?.target) ? error.meta.target.join(", ") : String(error.meta?.target ?? "");
      return NextResponse.json(
        { error: `Nilai duplikat pada ${target || "field unik"} — sudah dipakai produk/varian lain.` },
        { status: 409 },
      );
    }
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal menyimpan produk." },
      { status: 400 },
    );
  }

  // Sync search index non-blocking via after() — sebelumnya fire-and-forget
  // promise yang bisa dibekukan Vercel sebelum jalan → produk baru tidak
  // muncul di pencarian sampai sync berikutnya (index basi). Sama dengan
  // pola di bulk route.
  after(() =>
    syncProduct(created.id).catch((err) => {
      console.error("[admin/products POST syncProduct]", err);
    }),
  );

  if (!hasVideo) return NextResponse.json({ ...created, creationState: "ready", requiresVideoFinalize: false }, { status: 201 });
  return NextResponse.json({ ...created, creationState: "creating", requiresVideoFinalize: true }, { status: 201 });
}
