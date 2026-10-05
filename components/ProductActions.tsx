"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ProductQuantitySelector } from "@/components/products/ProductQuantitySelector";
import type { StoreProduct } from "@/lib/products";
import { addItemToCart } from "@/lib/cart-actions";
import { AddToCartBottomSheet } from "@/components/AddToCartBottomSheet";

const CHECKOUT_SELECTION_KEY = "checkout:selectedCartItems";

export function ProductActions({ product }: { product: StoreProduct }) {
  const router = useRouter();
  const [sheetOpen, setSheetOpen] = useState(false);
  const price =
    product.discountPrice !== null && product.discountPrice < product.price
      ? product.discountPrice
      : product.price;
  const outOfStock = product.stock === 0;
  const minimumQuantity = (product as StoreProduct & { minimumQuantity?: number | null })
    .minimumQuantity;

  const minimum = Math.max(1, Math.floor(minimumQuantity ?? 1));
  const [quantity, setQuantity] = useState(Math.min(product.stock, minimum));

  const sheetItem = useMemo(
    () => ({
      productId: product.id,
      variantId: null,
      variantLabel: null,
      name: product.name,
      price,
      weightGram: product.weightGram,
      imageUrl: product.imageUrl,
      stock: product.stock,
      minimumQuantity,
    }),
    [minimumQuantity, price, product.id, product.imageUrl, product.name, product.stock, product.weightGram],
  );

  useEffect(() => {
    function addToCart(redirectToCheckout = false) {
      if (outOfStock) return;
      const requestedQuantity = window.matchMedia("(min-width: 768px)").matches ? Math.min(quantity, product.stock) : minimum;
      if (requestedQuantity < minimum || requestedQuantity > product.stock) return;

      const cartItem = {
        productId: product.id,
        slug: product.slug,
        variantId: null,
        variantLabel: null,
        name: product.name,
        price,
        quantity: requestedQuantity,
        subtotal: price * requestedQuantity,
        weightGram: product.weightGram,
        imageUrl: product.imageUrl,
        stock: product.stock,
      };

      const result = addItemToCart(cartItem, { showToast: !redirectToCheckout });

      if (result.ok && redirectToCheckout) {
        // Scope checkout HANYA ke produk ini — jangan ambil seluruh cart user.
        // Mirror logic dari app/cart/page.tsx:checkoutSelected: tulis selection
        // ke sessionStorage + lewatkan cart_item_ids di query agar checkout
        // page filter ke item yg dipilih saja.
        const cartKey = `${product.id}:`;
        try {
          sessionStorage.setItem(
            CHECKOUT_SELECTION_KEY,
            JSON.stringify([cartItem]),
          );
        } catch {
          // sessionStorage might fail in private mode — checkout still works
          // via existing cart, just without scoped selection.
        }
        router.push(`/checkout?cart_item_ids=${encodeURIComponent(cartKey)}`);
      }
    }

    function onAddToCart() {
      if (window.matchMedia("(min-width: 768px)").matches) addToCart();
      else if (!outOfStock) setSheetOpen(true);
    }

    function onBuyNow() {
      addToCart(true);
    }

    window.addEventListener("pdp-add-to-cart", onAddToCart);
    window.addEventListener("pdp-buy-now", onBuyNow);
    return () => {
      window.removeEventListener("pdp-add-to-cart", onAddToCart);
      window.removeEventListener("pdp-buy-now", onBuyNow);
    };
  }, [outOfStock, price, product, router, quantity, minimum]);

  return (
    <>
    <ProductQuantitySelector quantity={quantity} stock={product.stock} minimum={minimum} onChange={setQuantity} />
    <AddToCartBottomSheet
      open={sheetOpen}
      item={sheetItem}
      onClose={() => setSheetOpen(false)}
    />
    </>
  );
}
