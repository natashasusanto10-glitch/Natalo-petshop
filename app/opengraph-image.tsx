import { ImageResponse } from "next/og";

/**
 * Root Open Graph image — render saat user share link homepage Natalo
 * (mis. natalo-petshop.vercel.app/) ke WhatsApp / Facebook / Twitter / Slack.
 *
 * Output: 1200×630 px PNG (standard OG size). Brand blue background +
 * Natalo logo + tagline. Per-page bisa override dengan opengraph-image.tsx
 * di route segment masing-masing (mis. products/[slug]).
 */

export const runtime = "edge";
export const alt = "Natalo Petshop & Aquarium — Toko Hewan Peliharaan Medan";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          background: "linear-gradient(135deg, #1E5FBF 0%, #143E7E 100%)",
          color: "white",
          fontFamily: "sans-serif",
          padding: "60px 80px",
        }}
      >
        {/* Logo + brand mark */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "24px",
            marginBottom: "40px",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              width: "120px",
              height: "120px",
              borderRadius: "30px",
              background: "rgba(255,255,255,0.18)",
              fontSize: "78px",
              fontWeight: 900,
              letterSpacing: "-0.05em",
            }}
          >
            🐾
          </div>
          <div style={{ display: "flex", flexDirection: "column" }}>
            <div
              style={{
                fontSize: "84px",
                fontWeight: 900,
                letterSpacing: "-0.04em",
                lineHeight: 0.95,
              }}
            >
              Natalo
            </div>
            <div
              style={{
                fontSize: "32px",
                fontWeight: 600,
                opacity: 0.85,
                letterSpacing: "0.18em",
                marginTop: "8px",
                textTransform: "uppercase",
              }}
            >
              Petshop · Aquarium
            </div>
          </div>
        </div>

        {/* Tagline */}
        <div
          style={{
            fontSize: "44px",
            fontWeight: 700,
            textAlign: "center",
            maxWidth: "880px",
            lineHeight: 1.25,
            marginBottom: "30px",
          }}
        >
          Toko Hewan Peliharaan Terpercaya di Medan
        </div>

        {/* Sub-info */}
        <div
          style={{
            display: "flex",
            gap: "32px",
            fontSize: "24px",
            fontWeight: 600,
            opacity: 0.85,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <span>🚚</span>
            <span>Pengiriman Cepat</span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <span>⭐</span>
            <span>7+ Tahun</span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <span>💯</span>
            <span>Brand Original</span>
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
