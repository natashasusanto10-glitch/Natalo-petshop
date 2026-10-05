import React from "react";
import BrandManager from "../../components/admin/BrandManager";
const seed = [
  ["Royal Canin", 164, "#bc2635", true],
  ["Pro Plan", 42, "#343b48", true],
  ["Angels Pet", 57, "#b28b32", true],
  ["CIAO / INABA", 19, "#c53e40", true],
  ["Acana", 6, "#466443", true],
  ["Friskies", 21, "#b67b14", true],
  ["Happy Dog", 54, "#47638a", true],
  ["Happy Cat", 36, "#86558a", true],
  ["Kaniva", 11, "#718967", false],
  ["Animal & Co", 22, "#735c9a", true],
  ["Meong", 2, "#468383", false],
  ["Bioline", 2, "#638569", false],
].map(([name, products, color, hasLogo], index) => ({
  id: `brand-demo-${index}`,
  slug: name.toLowerCase().replace(/[^a-z0-9]+/g, "-"),
  position: index,
  name,
  products,
  color,
  hasLogo,
  logoUrl: hasLogo
    ? `data:image/svg+xml,${encodeURIComponent(
        `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="60"><text x="60" y="40" text-anchor="middle" font-family="Arial" font-weight="bold" font-size="22" fill="${color}">${name
          .split(/[ /&]+/)
          .filter(Boolean)
          .map((w) => w[0])
          .slice(0, 2)
          .join("")}</text></svg>`
      )}`
    : null,
  active: index !== 11,
}));

export default function BrandImplementationReview() {
  return (
    <BrandManager
      initialBrands={seed}
      needsReviewCount={18}
      noBrandCount={4}
      saveOrderAction={async () => {}}
      deleteBrandAction={async () => {}}
      saveBrandAction={async (data) => {
        const id = data.get("id");
        const existing = seed.find((b) => b.id === id);
        return {
          ...existing,
          id: id || `local-${Date.now()}`,
          name: data.get("name"),
          slug: existing?.slug || data.get("name").toLowerCase(),
          logoUrl: data.get("logoUrl") || null,
          hasLogo: Boolean(data.get("logoUrl")),
          active: data.get("isActive") === "on",
          products: existing?.products || 0,
          position: existing?.position ?? 1000,
        };
      }}
    />
  );
}
