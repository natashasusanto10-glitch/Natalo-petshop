"use client";
import { ProductForm } from "./ProductForm";
export function NewProductForm(props: { categories: Array<{ id: string; name: string }>; brands: Array<{ id: string; name: string }> }) {
  return <ProductForm mode="create" {...props} />;
}
