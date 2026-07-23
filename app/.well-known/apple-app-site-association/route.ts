/**
 * Apple App Site Association (AASA) — required oleh iOS untuk Universal Links.
 *
 * URL harus tepat:
 * - https://www.natalopetshop.com/.well-known/apple-app-site-association
 * - https://natalopetshop.com/.well-known/apple-app-site-association
 * - https://natalo-petshop.vercel.app/.well-known/apple-app-site-association
 * Apple validate file ini saat user pertama install app + periodically refresh.
 *
 * Tanpa file ini, link ke domain Natalo akan buka di Safari (default behavior),
 * bukan langsung ke app native. Dengan AASA + entitlement valid:
 * - User klik link "www.natalopetshop.com/products/royal-canin" di WhatsApp
 * - iOS check apakah ada app yang claim domain ini → ya, Natalo
 * - iOS open Natalo app, pass URL → app navigate ke product detail
 *
 * Format reference: https://developer.apple.com/documentation/xcode/supporting-associated-domains
 */

import { NextResponse } from "next/server";

// Apple Developer Team ID (dari cert log saat first build)
const TEAM_ID = "87FXPV558A";
const BUNDLE_ID = "com.natalo.petshop";

const aasa = {
  applinks: {
    details: [
      {
        appIDs: [`${TEAM_ID}.${BUNDLE_ID}`],
        components: [
          // Halaman yang harus dibuka di app native (bukan Safari)
          { "/": "/feed/*", comment: "Public Feed post pages" },
          { "/": "/products/*", comment: "Product detail pages" },
          { "/": "/produk/*", comment: "Product detail aliases" },
          { "/": "/kategori/*", comment: "Category pages" },
          { "/": "/pesanan/*", comment: "Order detail / tracking" },
          { "/": "/order-status/*", comment: "Order status lookup" },
          { "/": "/wishlist", comment: "Wishlist" },
          { "/": "/cart", comment: "Shopping cart" },
          { "/": "/member/*", comment: "Member account pages" },
          { "/": "/u/*", comment: "Public profile pages (@username)" },
          // Exclude paths yang harus tetap di browser (admin)
          { "/": "/admin/*", exclude: true, comment: "Admin tetap di browser" },
        ],
      },
    ],
  },
  // webcredentials: optional, untuk autofill password ASWebAuthenticationSession
  webcredentials: {
    apps: [`${TEAM_ID}.${BUNDLE_ID}`],
  },
};

export async function GET() {
  return new NextResponse(JSON.stringify(aasa, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
