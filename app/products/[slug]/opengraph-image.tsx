import { ImageResponse } from "next/og";
import { getProductBySlug } from "@/lib/products";
import { formatRupiah } from "@/lib/format";

/**
 * Per-product Open Graph image — render saat user share link product detail
 * Natalo (mis. natalo-petshop.vercel.app/products/royal-canin-persian-adult-2kg)
 * ke WhatsApp / Facebook / Twitter / Telegram.
 *
 * Auto-fetch product info, render card dengan:
 * - Product image (kalau ada)
 * - Product name + brand
 * - Harga + diskon kalau ada
 * - Natalo brand stripe
 *
 * Output: 1200×630 px PNG. Konsumer share link → preview card menarik → click-thru rate naik.
 */

export const runtime = "nodejs"; // Pakai nodejs runtime karena akses Prisma
export const alt = "Produk Natalo Petshop";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function ProductOgImage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const product = await getProductBySlug(slug).catch(() => null);

  if (!product) {
    // Fallback OG untuk product yang tidak ditemukan
    return new ImageResponse(
      (
        <div
          style={{
            width: "100%",
            height: "100%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: "linear-gradient(135deg, #1E5FBF 0%, #143E7E 100%)",
            color: "white",
            fontSize: "60px",
            fontWeight: 900,
            fontFamily: "sans-serif",
          }}
        >
          🐾 Natalo Petshop
        </div>
      ),
      { ...size },
    );
  }

  const hasDiscount =
    product.discountPrice !== null && product.discountPrice < product.price;
  const displayPrice = hasDiscount ? product.discountPrice! : product.price;
  const discountPercent = hasDiscount
    ? Math.round(((product.price - product.discountPrice!) / product.price) * 100)
    : null;

  const productImage = product.imageUrl
    ? product.imageUrl.startsWith("http")
      ? product.imageUrl
      : `${process.env.NEXT_PUBLIC_SITE_URL || "https://natalo-petshop.vercel.app"}${product.imageUrl}`
    : null;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          background: "#ffffff",
          fontFamily: "sans-serif",
        }}
      >
        {/* Left: product image (60%) */}
        <div
          style={{
            width: "55%",
            height: "100%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: "linear-gradient(135deg, #EFF6FF 0%, #DBEAFE 100%)",
            position: "relative",
          }}
        >
          {productImage ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={productImage}
              alt={product.name}
              width={500}
              height={500}
              style={{
                width: "85%",
                height: "85%",
                objectFit: "contain",
                borderRadius: "20px",
              }}
            />
          ) : (
            <div
              style={{
                fontSize: "200px",
              }}
            >
              🐾
            </div>
          )}

          {hasDiscount && (
            <div
              style={{
                position: "absolute",
                top: "32px",
                right: "32px",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                background: "#dc2626",
                color: "white",
                width: "90px",
                height: "90px",
                borderRadius: "50%",
                fontSize: "28px",
                fontWeight: 900,
                boxShadow: "0 8px 20px rgba(220, 38, 38, 0.35)",
              }}
            >
              -{discountPercent}%
            </div>
          )}
        </div>

        {/* Right: product info (45%) */}
        <div
          style={{
            width: "45%",
            height: "100%",
            display: "flex",
            flexDirection: "column",
            justifyContent: "space-between",
            padding: "50px 50px 40px",
          }}
        >
          {/* Top: brand strip */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: "12px",
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                width: "50px",
                height: "50px",
                borderRadius: "12px",
                background: "#1E5FBF",
                color: "white",
                fontSize: "28px",
                fontWeight: 900,
              }}
            >
              N
            </div>
            <div
              style={{
                fontSize: "20px",
                fontWeight: 800,
                color: "#143E7E",
                letterSpacing: "0.05em",
              }}
            >
              NATALO PETSHOP
            </div>
          </div>

          {/* Middle: product name */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: "16px",
              flex: 1,
              justifyContent: "center",
            }}
          >
            <div
              style={{
                fontSize: "42px",
                fontWeight: 900,
                color: "#0F172A",
                lineHeight: 1.15,
                letterSpacing: "-0.02em",
                // Limit ke 4 baris
                display: "-webkit-box",
                WebkitLineClamp: 4,
                WebkitBoxOrient: "vertical",
                overflow: "hidden",
              }}
            >
              {product.name}
            </div>

            {/* Rating badge if reviews exist */}
            {product.reviewCount > 0 && (
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "8px",
                  fontSize: "20px",
                  color: "#475569",
                  fontWeight: 600,
                }}
              >
                <span>⭐</span>
                <span>
                  {product.avgRating.toFixed(1)} ({product.reviewCount} review)
                </span>
              </div>
            )}
          </div>

          {/* Bottom: price */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: "6px",
            }}
          >
            {hasDiscount && (
              <div
                style={{
                  fontSize: "22px",
                  color: "#94A3B8",
                  textDecoration: "line-through",
                  fontWeight: 600,
                }}
              >
                {formatRupiah(product.price)}
              </div>
            )}
            <div
              style={{
                fontSize: "48px",
                fontWeight: 900,
                color: "#1E5FBF",
                letterSpacing: "-0.02em",
              }}
            >
              {formatRupiah(displayPrice)}
            </div>
            <div
              style={{
                marginTop: "12px",
                fontSize: "18px",
                color: "#475569",
                fontWeight: 600,
              }}
            >
              🚚 Pengiriman cepat dari Medan
            </div>
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
