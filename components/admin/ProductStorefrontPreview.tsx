"use client";

import { useId, useState } from "react";
import { ProductImageCarousel } from "@/components/ProductImageCarousel";
import { PriceBlock } from "@/components/products/PriceBlock";
import { SocialProofRow } from "@/components/products/SocialProofRow";
import { MarkdownBody } from "@/components/products/ProductTabs";
import {
  mapCatalogProduct,
  type CatalogProductInput,
} from "@/lib/product/catalog-product";
import { productVideoMp4 } from "@/lib/product/product-video-url";
import type { VariantEditorDraftPayload } from "./VariantEditor";

type Props = {
  input: CatalogProductInput;
  draft: VariantEditorDraftPayload;
  categoryName?: string;
  draftVideoUrl?: string;
};

export function ProductStorefrontPreview({
  input,
  draft,
  categoryName,
  draftVideoUrl,
}: Props) {
  const [selection, setSelection] = useState<string[]>([]);
  const panelId = useId();
  const catalog = mapCatalogProduct(input);
  const validSelection = draft.attributes.map((attribute, index) =>
    attribute.options.some(
      (option) => `${index}:${option.value}` === selection[index]
    )
      ? selection[index]
      : ""
  );
  const selected =
    input.hasVariants && draft.attributes.length > 0
      ? draft.variants.find(
          (variant) =>
            variant.isActive &&
            draft.attributes.every(
              (_, index) =>
                Boolean(validSelection[index]) &&
                variant.optionRefs.includes(validSelection[index])
            )
        )
      : undefined;
  const selectedInput =
    selected && input.variants.find((variant) => variant.id === selected.id);
  // Keep exactly the catalog discount resolver, including promotions attached to a variant.
  const detail = selected
    ? mapCatalogProduct({
        ...input,
        variants: [
          selectedInput ?? {
            id: selected.id ?? "preview-selected",
            price: selected.price,
            stock: selected.stock,
          },
        ],
      })
    : catalog;
  const effectivePrice = detail.discountPrice ?? detail.price;
  const images = [input.imageUrl, ...input.gallery].filter(
    (image): image is string => Boolean(image)
  );
  const galleryImages = selected?.imageUrl
    ? [
        selected.imageUrl,
        ...images.filter((image) => image !== selected.imageUrl),
      ]
    : images;
  const publishedMp4 = productVideoMp4(input.videoUrl, 1080);
  const video = draftVideoUrl
    ? {
        mp4Url: draftVideoUrl,
        thumbnailUrl: input.imageUrl ?? "",
        durationSec: input.videoDurationSec,
      }
    : input.videoStatus === "ready" && publishedMp4 && input.videoThumbnailUrl
    ? {
        mp4Url: publishedMp4,
        mp4FallbackUrl: productVideoMp4(input.videoUrl, 720) ?? undefined,
        thumbnailUrl: input.videoThumbnailUrl,
        durationSec: input.videoDurationSec,
      }
    : undefined;

  return (
    <aside
      className="admin-preview-panel admin-detail-preview-panel"
      aria-label="Pratinjau tampilan Flutter app"
    >
      <p className="admin-preview-label">PRATINJAU APP</p>
      <div id={panelId}>
          <div className="admin-product-detail-preview">
            <div className="flex items-center justify-between border-b border-gray-100 bg-white px-3 py-3 text-gray-900" aria-label="Header aplikasi">
              <span aria-hidden="true">←</span><span className="text-sm font-semibold">Detail Produk</span><span className="flex gap-3" aria-hidden="true"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M12 16V3m-4 4 4-4 4 4M5 11v9h14v-9" /></svg><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="m3 3 2 2 3 11h11l2-9H6M9 20h.01M18 20h.01" /></svg></span>
            </div>
            <div
              className="admin-preview-scroll"
              tabIndex={0}
              aria-label="Isi halaman detail produk"
            >
              <div className="admin-preview-gallery">
                <ProductImageCarousel
                  key={galleryImages.join("|") + (video?.mp4Url ?? "")}
                  images={galleryImages}
                  alt={input.name}
                  video={video}
                  showThumbnails={false}
                />
              </div>
              <section className="admin-preview-details">
                <PriceBlock
                  productId={input.id}
                  price={effectivePrice}
                  originalPrice={detail.discountPrice ? detail.price : null}
                  discountPercent={
                    detail.discountPrice && detail.price > 0
                      ? Math.round((1 - effectivePrice / detail.price) * 100)
                      : null
                  }
                  initialFavorited={false}
                  showFavorite={false}
                />
                <h2 className="mt-3 text-base font-bold text-gray-900">
                  {input.name}
                </h2>
                <SocialProofRow
                  avgRating={input.avgRating}
                  reviewCount={input.reviewCount}
                />
                {input.hasVariants && (
                  <div className="admin-preview-variations">
                    {draft.attributes.map((attribute, index) => (
                      <fieldset key={index}>
                        <legend>{attribute.name || "Variasi"}</legend>
                        <div className="admin-preview-options">
                          {attribute.options
                            .filter((option) => option.value.trim())
                            .map((option) => {
                              const ref = `${index}:${option.value}`;
                              return (
                                <button
                                  key={ref}
                                  type="button"
                                  aria-pressed={selection[index] === ref}
                                  onClick={() =>
                                    setSelection((previous) => {
                                      const next = [...previous];
                                      next[index] =
                                        previous[index] === ref ? "" : ref;
                                      return next;
                                    })
                                  }
                                >
                                  {option.value}
                                </button>
                              );
                            })}
                        </div>
                      </fieldset>
                    ))}
                    {selected && (
                      <p className="admin-preview-variant-stock" role="status">
                        Stok varian: {selected.stock}
                      </p>
                    )}
                    {!selected &&
                      draft.attributes.length > 0 &&
                      draft.attributes.every(
                        (_, index) => validSelection[index]
                      ) && (
                        <p
                          className="admin-preview-variant-stock"
                          role="status"
                        >
                          Kombinasi tidak tersedia
                        </p>
                      )}
                  </div>
                )}
              </section>
              <div className="mx-4 divide-y divide-gray-200 text-xs text-gray-700">
                <p className="flex items-center justify-between py-4"><span>Pengiriman · Stok {detail.stock}</span><span aria-hidden="true">›</span></p>
                <p className="flex items-center justify-between py-4"><span>Belanja aman · Sesuai kebijakan Natalo</span><span aria-hidden="true">›</span></p>
              </div>
              <div className="border-y border-gray-100 bg-white px-4 py-3 text-center text-sm font-semibold text-blue-600">Detail</div>
              <section className="admin-preview-description">
                <h3>Deskripsi</h3>
                <MarkdownBody body={input.description} />
                <dl className="admin-preview-specs">
                  {categoryName && (
                    <div>
                      <dt>Kategori</dt>
                      <dd>{categoryName}</dd>
                    </div>
                  )}
                  {input.brand?.name && (
                    <div>
                      <dt>Brand</dt>
                      <dd>{input.brand.name}</dd>
                    </div>
                  )}
                </dl>
              </section>
            </div>
            <div
              className="admin-preview-purchase"
              aria-label="Contoh tombol pembelian, tidak aktif pada pratinjau"
            >
              <button type="button" disabled>
                Chat
              </button>
              <button type="button" disabled>
                {detail.stock <= 0
                  ? "Stok Habis"
                  : input.hasVariants && !selected
                  ? "Pilih Varian"
                  : "Beli Sekarang"}
              </button>
              <button type="button" disabled>
                + Keranjang
              </button>
            </div>
          </div>
      </div>
    </aside>
  );
}
