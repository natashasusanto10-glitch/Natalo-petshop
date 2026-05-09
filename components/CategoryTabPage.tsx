"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import {
  isCategoryCacheFresh,
  readCategoryCache,
  writeCategoryCache,
} from "@/lib/client-performance";

export type CategorySummary = {
  id: string;
  name: string;
  slug: string;
  productCount: number;
  imageUrl: string | null;
};

type Props = {
  initialCategories: CategorySummary[];
};

export function CategoryTabPage({ initialCategories }: Props) {
  const [categories, setCategories] = useState<CategorySummary[]>(initialCategories);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (initialCategories.length > 0) writeCategoryCache(initialCategories);
  }, [initialCategories]);

  useEffect(() => {
    let cancelled = false;
    const cached = readCategoryCache();

    if (cached?.categories.length) {
      setCategories(cached.categories);
    }

    if (isCategoryCacheFresh(cached) && (cached?.categories.length || categories.length > 0)) {
      return;
    }

    setRefreshing(Boolean(cached?.categories.length || categories.length > 0));
    fetch("/api/categories", { cache: "force-cache" })
      .then((response) => {
        if (!response.ok) throw new Error("Gagal memuat kategori.");
        return response.json();
      })
      .then((payload) => {
        if (cancelled || !Array.isArray(payload?.categories)) return;
        setCategories((current) => {
          const next = payload.categories as CategorySummary[];
          if (JSON.stringify(current) === JSON.stringify(next)) return current;
          return next;
        });
        writeCategoryCache(payload.categories);
        setError("");
      })
      .catch(() => {
        if (!cancelled) setError("Kategori belum bisa diperbarui. Menampilkan data terakhir.");
      })
      .finally(() => {
        if (!cancelled) setRefreshing(false);
      });

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="mx-auto max-w-6xl px-4 py-4 md:py-10">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black text-gray-900 md:text-3xl">Kategori</h1>
          <p className="mt-1 text-sm text-gray-500">
            Pilih kebutuhan hewan peliharaanmu tanpa menunggu halaman kosong.
          </p>
        </div>
        {refreshing && (
          <span className="mt-1 shrink-0 rounded-full bg-natalo-50 px-3 py-1 text-xs font-bold text-natalo-700">
            Memperbarui...
          </span>
        )}
      </div>

      {error && categories.length > 0 && (
        <p className="mt-3 rounded-xl bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-700">
          {error}
        </p>
      )}

      {categories.length === 0 ? (
        <CategorySkeleton />
      ) : (
        <>
          <div className="-mx-4 mt-5 flex gap-2 overflow-x-auto px-4 pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden md:mx-0 md:flex-wrap md:px-0">
            <Link
              href="/products"
              prefetch
              className="shrink-0 rounded-full bg-natalo-600 px-4 py-2 text-sm font-bold text-white transition hover:bg-natalo-700"
            >
              Semua Produk
            </Link>
            {categories.slice(0, 8).map((category) => (
              <Link
                key={category.id}
                href={`/products?kategori=${category.slug}`}
                prefetch
                className="shrink-0 rounded-full border border-gray-200 bg-white px-4 py-2 text-sm font-semibold text-gray-600 transition hover:border-natalo-300 hover:text-natalo-600"
              >
                {category.name}
              </Link>
            ))}
          </div>

          <div className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {categories.map((category, index) => (
              <Link
                key={category.id}
                href={`/products?kategori=${category.slug}`}
                prefetch
                className="group overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm transition active:opacity-90 sm:hover:border-natalo-200 sm:hover:shadow-md"
              >
                <div className="relative aspect-[4/3] bg-natalo-50">
                  {category.imageUrl ? (
                    <Image
                      src={category.imageUrl}
                      alt={category.name}
                      fill
                      loading={index < 4 ? "eager" : "lazy"}
                      sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 25vw"
                      className="object-cover transition group-hover:scale-105"
                    />
                  ) : (
                    <div className="flex h-full items-center justify-center text-4xl text-natalo-300">
                      🐾
                    </div>
                  )}
                </div>
                <div className="p-3">
                  <p className="line-clamp-1 font-black text-gray-900">{category.name}</p>
                  <p className="mt-0.5 text-xs font-semibold text-gray-500">
                    {category.productCount.toLocaleString("id-ID")} produk
                  </p>
                </div>
              </Link>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

function CategorySkeleton() {
  return (
    <div className="mt-5">
      <div className="flex gap-2 overflow-hidden">
        {[0, 1, 2, 3].map((item) => (
          <div key={item} className="h-9 w-24 shrink-0 animate-pulse rounded-full bg-gray-100" />
        ))}
      </div>
      <div className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        {[0, 1, 2, 3, 4, 5].map((item) => (
          <div key={item} className="overflow-hidden rounded-2xl border border-gray-100 bg-white">
            <div className="aspect-[4/3] animate-pulse bg-gray-100" />
            <div className="space-y-2 p-3">
              <div className="h-4 w-2/3 animate-pulse rounded bg-gray-100" />
              <div className="h-3 w-1/2 animate-pulse rounded bg-gray-100" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
