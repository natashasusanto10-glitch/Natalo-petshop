import assert from "node:assert/strict";
import test from "node:test";
import {
  serializeCartRecommendationProduct,
  type CartRecommendationProductRow,
} from "@/lib/cart-recommendation-products";

// Row minimal — hanya field yang dibaca serializer; sisanya di-cast.
function makeRow(
  overrides: Partial<CartRecommendationProductRow> = {}
): CartRecommendationProductRow {
  return {
    id: "p1",
    slug: "me-o-7kg",
    name: "Me-O 7KG",
    price: 387000,
    discountPrice: null,
    flashSaleEndsAt: null,
    imageUrl: null,
    stock: 5,
    weightGram: 7000,
    avgRating: 0,
    reviewCount: 0,
    hasVariants: false,
    categoryId: "cat-catfood",
    brandId: "brand-meo",
    category: { id: "cat-catfood", name: "Makanan Kucing", slug: "makanan-kucing" },
    brand: { id: "brand-meo", name: "Me-O", slug: "me-o" },
    variantAttrs: [],
    variants: [],
    discountItems: [],
    ...overrides,
  } as unknown as CartRecommendationProductRow;
}

test("serializeCartRecommendationProduct: meneruskan brandId (untuk voucher brand-exclusive)", () => {
  const dto = serializeCartRecommendationProduct(makeRow());
  assert.equal(
    (dto as { brandId?: string | null }).brandId,
    "brand-meo",
    "brandId harus diteruskan supaya voucherMatchesProduct bisa cocokkan voucher brand-exclusive di kartu rekomendasi/recently-viewed"
  );
});

test("serializeCartRecommendationProduct: brandId null saat produk tanpa brand", () => {
  const dto = serializeCartRecommendationProduct(
    makeRow({ brandId: null, brand: null } as Partial<CartRecommendationProductRow>)
  );
  assert.equal((dto as { brandId?: string | null }).brandId, null);
});
