import assert from "node:assert/strict";
import test from "node:test";
import { addItemsToCart } from "@/lib/cart-actions";
import { loadCart } from "@/lib/cart";
import {
  buildBuyAgainResponse,
  getBuyAgainCandidates,
  skippedToUnavailable,
  toBuyAgainAddedItem,
} from "@/lib/buy-again";
import {
  buildReorderResult,
  validateReorderByOrderIdWithRepository,
  validateReorderWithRepository,
  type ReorderCurrentProduct,
  type ReorderCurrentVariant,
  type ReorderOrder,
  type ReorderRepository,
} from "@/lib/reorder";

function product(overrides: Partial<ReorderCurrentProduct> = {}): ReorderCurrentProduct {
  return {
    id: "product-1",
    name: "Friskies Party Mix 60g",
    price: 15000,
    discountPrice: null,
    stock: 10,
    weightGram: 60,
    imageUrl: "/friskies.jpg",
    isActive: true,
    hasVariants: false,
    ...overrides,
  };
}

function variant(overrides: Partial<ReorderCurrentVariant> = {}): ReorderCurrentVariant {
  return {
    id: "variant-1",
    productId: "product-1",
    price: 17000,
    stock: 10,
    weightGram: 60,
    imageUrl: "/variant.jpg",
    isActive: true,
    deletedAt: null,
    ...overrides,
  };
}

function order(overrides: Partial<ReorderOrder> = {}): ReorderOrder {
  return {
    orderNumber: "ORD-001",
    items: [
      {
        id: "order-item-1",
        productId: "product-1",
        variantId: null,
        variantLabel: null,
        name: "Friskies Party Mix 60g",
        price: 12000,
        quantity: 2,
      },
    ],
    ...overrides,
  };
}

function setupBrowserCart(initialItems: unknown[] = []) {
  const store = new Map<string, string>();
  store.set("cart:owner", "guest");
  store.set("cart:guest", JSON.stringify(initialItems));

  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => store.set(key, value),
      removeItem: (key: string) => store.delete(key),
    },
  });

  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: {
      dispatchEvent: () => undefined,
    },
  });
}

test("reorder adds all available items using current price and stock", () => {
  const result = buildReorderResult(order(), [product({ discountPrice: 11000 })], []);

  assert.equal(result.added.length, 1);
  assert.equal(result.added[0].item.price, 11000);
  assert.equal(result.added[0].item.stock, 10);
  assert.equal(result.added[0].item.quantity, 2);
  assert.equal(result.added[0].priceChanged, true);
  assert.equal(result.skipped.length, 0);
});

test("reorder treats old order fields as snapshots and uses current product data for cart", () => {
  const result = buildReorderResult(
    order({
      items: [
        {
          id: "snapshot-item",
          productId: "product-1",
          variantId: "variant-1",
          productNameSnapshot: "Friskies Party Mix Nama Lama",
          variantNameSnapshot: "Varian Lama",
          priceSnapshot: 20000,
          quantity: 9,
        },
      ],
    }),
    [product({ name: "Friskies Party Mix 60g Cat Treats", hasVariants: true })],
    [variant({ id: "variant-1", label: "Beachside", price: 22000, stock: 5 })],
  );

  assert.equal(result.adjusted.length, 1);
  assert.equal(result.adjusted[0].item.name, "Friskies Party Mix 60g Cat Treats");
  assert.equal(result.adjusted[0].item.variantLabel, "Beachside");
  assert.equal(result.adjusted[0].item.price, 22000);
  assert.equal(result.adjusted[0].previousPrice, 20000);
  assert.equal(result.adjusted[0].requestedQuantity, 9);
  assert.equal(result.adjusted[0].availableStock, 5);
});

test("reorder skips unavailable and out-of-stock items", () => {
  const result = buildReorderResult(
    order({
      items: [
        {
          id: "inactive-product",
          productId: "inactive-product",
          variantId: null,
          variantLabel: null,
          name: "Inactive",
          price: 1000,
          quantity: 1,
        },
        {
          id: "stock-empty",
          productId: "stock-empty",
          variantId: null,
          variantLabel: null,
          name: "Empty",
          price: 1000,
          quantity: 1,
        },
      ],
    }),
    [
      product({ id: "inactive-product", isActive: false }),
      product({ id: "stock-empty", stock: 0 }),
    ],
    [],
  );

  assert.deepEqual(
    result.skipped.map((item) => item.reasonCode),
    ["PRODUCT_INACTIVE", "OUT_OF_STOCK"],
  );
  assert.equal(result.skipped[0].reason, "Produk tidak aktif.");
  assert.equal(result.added.length, 0);
});

test("reorder skips deleted product", () => {
  const result = buildReorderResult(order(), [], []);

  assert.equal(result.skipped[0].reasonCode, "PRODUCT_UNAVAILABLE");
  assert.equal(result.added.length, 0);
});

test("reorder skips deleted or inactive variant", () => {
  const oldOrder = order({
    items: [
      {
        id: "classic",
        productId: "product-1",
        variantId: "classic",
        variantLabel: "Classic",
        name: "Friskies Party Mix 60g",
        price: 15000,
        quantity: 1,
      },
      {
        id: "beachside",
        productId: "product-1",
        variantId: "beachside",
        variantLabel: "Beachside",
        name: "Friskies Party Mix 60g",
        price: 15000,
        quantity: 1,
      },
    ],
  });

  const result = buildReorderResult(
    oldOrder,
    [product({ hasVariants: true })],
    [
      variant({ id: "classic", isActive: false }),
      variant({ id: "beachside", deletedAt: new Date("2026-01-01") }),
    ],
  );

  assert.deepEqual(
    result.skipped.map((item) => item.reasonCode),
    ["VARIANT_UNAVAILABLE", "VARIANT_UNAVAILABLE"],
  );
});

test("reorder adjusts quantity when current stock is lower than the previous order", () => {
  const result = buildReorderResult(order({ items: [{ ...order().items[0], quantity: 9 }] }), [
    product({ stock: 3 }),
  ], []);

  assert.equal(result.adjusted.length, 1);
  assert.equal(result.adjusted[0].requestedQuantity, 9);
  assert.equal(result.adjusted[0].availableStock, 3);
  assert.equal(result.adjusted[0].item.quantity, 3);
});

test("reorder uses variant-specific stock for Classic and Beachside", () => {
  const result = buildReorderResult(
    order({
      items: [
        {
          id: "classic-item",
          productId: "product-1",
          variantId: "classic",
          variantLabel: "Classic",
          name: "Friskies Party Mix 60g",
          price: 15000,
          quantity: 9,
        },
        {
          id: "beachside-item",
          productId: "product-1",
          variantId: "beachside",
          variantLabel: "Beachside",
          name: "Friskies Party Mix 60g",
          price: 15000,
          quantity: 9,
        },
      ],
    }),
    [product({ hasVariants: true })],
    [variant({ id: "classic", stock: 4 }), variant({ id: "beachside", stock: 3 })],
  );

  assert.equal(result.adjusted.length, 2);
  assert.deepEqual(
    result.adjusted.map((item) => [item.item.variantLabel, item.item.quantity]),
    [
      ["Classic", 4],
      ["Beachside", 3],
    ],
  );
});

test("reorder uses the current product or variant stock source because no branch stock layer exists", () => {
  const result = buildReorderResult(
    order({
      items: [
        {
          id: "leonardi-beachside",
          productId: "product-1",
          variantId: "beachside",
          variantLabel: "Beachside",
          name: "Friskies Party Mix 60g",
          price: 15000,
          quantity: 9,
        },
      ],
    }),
    [product({ hasVariants: true })],
    [variant({ id: "beachside", stock: 3 })],
  );

  assert.equal(result.adjusted[0].availableStock, 3);
  assert.equal(result.adjusted[0].item.stock, 3);
});

test("reorder repository scopes order lookup to authenticated user", async () => {
  let scopedUserId = "";
  const repository: ReorderRepository = {
    async findOrder(_orderNumber, userId) {
      scopedUserId = userId;
      return null;
    },
    async findProducts() {
      return [];
    },
    async findVariants() {
      return [];
    },
  };

  await assert.rejects(
    validateReorderWithRepository(repository, "ORD-OTHER", "user-1"),
    /bukan milik Anda/,
  );
  assert.equal(scopedUserId, "user-1");
});

test("buy-again endpoint can validate by order id scoped to authenticated user", async () => {
  let scopedOrderId = "";
  let scopedUserId = "";
  const repository: ReorderRepository = {
    async findOrder() {
      return null;
    },
    async findOrderById(orderId, userId) {
      scopedOrderId = orderId;
      scopedUserId = userId;
      return order();
    },
    async findProducts(productIds) {
      return productIds.map((id) => product({ id }));
    },
    async findVariants() {
      return [];
    },
  };

  const result = await validateReorderByOrderIdWithRepository(
    repository,
    "order-db-id",
    "user-1",
  );

  assert.equal(scopedOrderId, "order-db-id");
  assert.equal(scopedUserId, "user-1");
  assert.equal(result.added.length, 1);
});

test("buy-again response uses added_items and unavailable_items contract", () => {
  const result = buildReorderResult(
    order({
      items: [
        {
          id: "beachside-item",
          productId: "product-1",
          variantId: "beachside",
          variantLabel: "Beachside",
          name: "Friskies Party Mix 60g Cat Treats",
          price: 18000,
          quantity: 9,
        },
        {
          id: "old-product",
          productId: "old-product",
          variantId: "classic",
          variantLabel: "Classic",
          name: "Produk Lama",
          price: 10000,
          quantity: 1,
        },
      ],
    }),
    [product({ hasVariants: true, name: "Friskies Party Mix 60g Cat Treats" })],
    [variant({ id: "beachside", stock: 3, price: 20000 })],
  );
  const [candidate] = getBuyAgainCandidates(result);
  const response = buildBuyAgainResponse(
    [toBuyAgainAddedItem(candidate, 3)],
    result.skipped.map(skippedToUnavailable),
    28,
  );

  assert.equal(response.status, "success");
  assert.equal(response.message, "Beberapa produk berhasil ditambahkan ke keranjang.");
  assert.deepEqual(response.added_items[0], {
    product_id: "product-1",
    variant_id: "beachside",
    product_name: "Friskies Party Mix 60g Cat Treats",
    variant_name: "Beachside",
    requested_qty: 9,
    added_qty: 3,
    available_stock: 3,
    current_price: 20000,
    weight_gram: 60,
    image_url: "/variant.jpg",
  });
  assert.equal(response.unavailable_items[0].product_id, "old-product");
  assert.equal(response.unavailable_items[0].variant_name, "Classic");
  assert.equal(response.cart?.total_items, 28);
});

test("buy-again response uses failed status when no products can be added", () => {
  const result = buildReorderResult(
    order({
      items: [
        {
          id: "beachside-item",
          productId: "product-1",
          variantId: "beachside",
          variantLabel: "Beachside",
          name: "Friskies Party Mix 60g Cat Treats",
          price: 18000,
          quantity: 9,
        },
      ],
    }),
    [product({ hasVariants: true, name: "Friskies Party Mix 60g Cat Treats" })],
    [variant({ id: "beachside", stock: 0 })],
  );
  const response = buildBuyAgainResponse([], result.skipped.map(skippedToUnavailable), 28);

  assert.deepEqual(response, {
    status: "failed",
    message: "Tidak ada produk yang tersedia untuk dibeli lagi.",
    added_items: [],
    unavailable_items: [
      {
        product_id: "product-1",
        variant_id: "beachside",
        product_name: "Friskies Party Mix 60g Cat Treats",
        variant_name: "Beachside",
        reason: "Stok habis",
        available_stock: 0,
      },
    ],
  });
});

test("cart merges reorder quantity without exceeding current available stock", () => {
  setupBrowserCart([
    {
      productId: "product-1",
      variantId: "beachside",
      variantLabel: "Beachside",
      name: "Friskies Party Mix 60g",
      price: 15000,
      quantity: 2,
      subtotal: 30000,
      weightGram: 60,
      stock: 3,
      imageUrl: null,
    },
  ]);

  const result = addItemsToCart(
    [
      {
        productId: "product-1",
        variantId: "beachside",
        variantLabel: "Beachside",
        name: "Friskies Party Mix 60g",
        price: 17000,
        quantity: 3,
        weightGram: 60,
        stock: 3,
        imageUrl: null,
      },
    ],
    { showToast: false },
  );

  const [item] = loadCart();
  assert.equal(result.ok, true);
  assert.equal(result.adjustedCount, 1);
  assert.equal(item.quantity, 3);
  assert.equal(item.price, 17000);
});

test("cart rejects reorder merge when existing quantity is already at stock cap", () => {
  setupBrowserCart([
    {
      productId: "product-1",
      variantId: "classic",
      variantLabel: "Classic",
      name: "Friskies Party Mix 60g",
      price: 15000,
      quantity: 4,
      subtotal: 60000,
      weightGram: 60,
      stock: 4,
      imageUrl: null,
    },
  ]);

  const result = addItemsToCart(
    [
      {
        productId: "product-1",
        variantId: "classic",
        variantLabel: "Classic",
        name: "Friskies Party Mix 60g",
        price: 15000,
        quantity: 1,
        weightGram: 60,
        stock: 4,
        imageUrl: null,
      },
    ],
    { showToast: false },
  );

  assert.equal(result.ok, false);
  assert.equal(loadCart()[0].quantity, 4);
});
