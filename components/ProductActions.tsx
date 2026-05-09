"use client";

import { useEffect } from "react";
import { StoreProduct } from "@/lib/products";
import { addItemToCart } from "@/lib/cart-actions";

export function ProductActions({ product }: { product: StoreProduct }) {
  const price =
    product.discountPrice !== null && product.discountPrice < product.price
      ? product.discountPrice
      : product.price;
  const outOfStock = product.stock === 0;

  useEffect(() => {
    function addToCart(redirectToCheckout = false) {
      if (outOfStock) return;

      const result = addItemToCart(
        {
          productId: product.id,
          variantId: null,
          variantLabel: null,
          name: product.name,
          price,
          quantity: 1,
          subtotal: price,
          weightGram: product.weightGram,
          imageUrl: product.imageUrl,
          stock: product.stock,
        },
        { showToast: !redirectToCheckout },
      );

      if (result.ok && redirectToCheckout) {
        window.location.href = "/checkout";
      }
    }

    function onAddToCart() {
      addToCart(false);
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
  }, [outOfStock, price, product]);

  return null;
}
