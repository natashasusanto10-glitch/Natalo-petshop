// Generate App Store screenshots otomatis untuk Natalo Petshop.
//
// Pakai Playwright headless Chromium, render natalo-petshop.vercel.app di iPhone
// 14 Pro Max viewport (430×932 logical × DPR 3 = 1290×2796 native), screenshot,
// composite tagline overlay via sharp.
//
// Output: screenshots/appstore-67/01-home.png ... 05-tentang.png
// Ready upload ke App Store Connect → Distribution → Previews and Screenshots
// → iPhone 6.7" Display.
//
// Run: node scripts/generate-appstore-screenshots.mjs

import { chromium } from "playwright-core";
import sharp from "sharp";
import { mkdirSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const OUT_DIR = resolve(ROOT, "screenshots/appstore-67");

const BASE_URL = process.env.BASE_URL || "https://natalo-petshop.vercel.app";

// iPhone 14 Pro Max viewport (430×932 logical × 3 DPR = 1290×2796 native).
// Apple Required size untuk iPhone 6.7" Display.
const VIEWPORT = { width: 430, height: 932 };
const DPR = 3;
const FINAL_WIDTH = VIEWPORT.width * DPR; // 1290
const FINAL_HEIGHT = VIEWPORT.height * DPR; // 2796

const BRAND_BLUE = "#1E5FBF";
const BRAND_BLUE_DARK = "#0F2D5C";

const CONFIGS = [
  {
    file: "01-home.png",
    path: "/",
    tagline: "Belanja Kebutuhan",
    taglineLine2: "Hewan Peliharaan",
    subtagline: "Toko petshop & aquarium terpercaya di Medan",
  },
  {
    file: "02-products.png",
    path: "/products",
    tagline: "Ribuan Produk",
    taglineLine2: "Brand Original",
    subtagline: "Royal Canin, Whiskas, Pedigree, dan lainnya",
  },
  {
    file: "03-bantuan.png",
    path: "/bantuan",
    tagline: "Customer Service",
    taglineLine2: "Selalu Siap",
    subtagline: "WhatsApp + email, jam toko Senin-Sabtu",
  },
  {
    file: "04-tentang.png",
    path: "/tentang-kami",
    tagline: "7 Tahun Melayani",
    taglineLine2: "Pet Owner Medan",
    subtagline: "Toko fisik + online store, terpercaya",
  },
  {
    file: "05-privacy.png",
    path: "/kebijakan-privasi",
    tagline: "Data Aman",
    taglineLine2: "Privasi Terjaga",
    subtagline: "Compliant UU PDP Indonesia",
  },
];

/**
 * Generate SVG tagline overlay — top 25% of screenshot, gradient brand-blue
 * fading to transparent supaya screenshot di bawahnya masih visible.
 */
function createTaglineOverlay(config) {
  // Escape XML special chars di text content
  const escape = (s) =>
    s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");

  const main1 = escape(config.tagline);
  const main2 = escape(config.taglineLine2);
  const sub = escape(config.subtagline);

  // Total height overlay: 28% of canvas, gradient fade-out
  const overlayHeight = Math.round(FINAL_HEIGHT * 0.28);
  const gradientHeight = Math.round(FINAL_HEIGHT * 0.34); // gradient extends a bit beyond text

  return Buffer.from(`<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${FINAL_WIDTH}" height="${FINAL_HEIGHT}" viewBox="0 0 ${FINAL_WIDTH} ${FINAL_HEIGHT}">
  <defs>
    <linearGradient id="brand-gradient" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="${BRAND_BLUE_DARK}" stop-opacity="1"/>
      <stop offset="60%" stop-color="${BRAND_BLUE}" stop-opacity="0.95"/>
      <stop offset="100%" stop-color="${BRAND_BLUE}" stop-opacity="0"/>
    </linearGradient>
    <style>
      .tagline {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Nunito", sans-serif;
        font-weight: 900;
        fill: white;
        text-anchor: middle;
        letter-spacing: -0.02em;
      }
      .subtagline {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Nunito", sans-serif;
        font-weight: 600;
        fill: rgba(255,255,255,0.92);
        text-anchor: middle;
        letter-spacing: 0;
      }
    </style>
  </defs>
  <rect x="0" y="0" width="${FINAL_WIDTH}" height="${gradientHeight}" fill="url(#brand-gradient)"/>
  <text class="tagline" x="${FINAL_WIDTH / 2}" y="${overlayHeight * 0.38}" font-size="118">${main1}</text>
  <text class="tagline" x="${FINAL_WIDTH / 2}" y="${overlayHeight * 0.62}" font-size="118">${main2}</text>
  <text class="subtagline" x="${FINAL_WIDTH / 2}" y="${overlayHeight * 0.85}" font-size="46">${sub}</text>
</svg>
`);
}

async function generateOne(browser, config) {
  console.log(`\n📸 ${config.file}`);
  console.log(`   URL: ${BASE_URL}${config.path}`);
  console.log(`   Tagline: "${config.tagline} ${config.taglineLine2}"`);

  const ctx = await browser.newContext({
    viewport: VIEWPORT,
    deviceScaleFactor: DPR,
    isMobile: true,
    hasTouch: true,
    userAgent:
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
    // Set sessionStorage SEEN_KEY supaya splash overlay gak muncul, langsung
    // screenshot halaman utama
    storageState: {
      cookies: [],
      origins: [
        {
          origin: BASE_URL,
          localStorage: [],
        },
      ],
    },
  });

  const page = await ctx.newPage();

  // Block analytics / tracking scripts supaya lebih cepat load
  await page.route(/google-analytics|googletagmanager|facebook\.com\/tr|cdn-cgi/, (route) =>
    route.abort(),
  );

  await page.goto(BASE_URL + config.path, {
    waitUntil: "networkidle",
    timeout: 30000,
  });

  // Set sessionStorage biar splash overlay component skip animation
  await page.evaluate(() => {
    sessionStorage.setItem("natalo:splash-shown", "1");
  });
  // Reload supaya splash gak tampil di screenshot
  await page.reload({ waitUntil: "networkidle" });

  // Tunggu lazy load images + animations
  await page.waitForTimeout(2500);

  // Scroll sedikit ke bawah untuk show konten yang lebih representatif kalau
  // halaman punya hero/banner besar di top
  if (config.path === "/" || config.path === "/products") {
    await page.evaluate(() => window.scrollBy({ top: 200, behavior: "instant" }));
    await page.waitForTimeout(800);
  }

  const screenshotBuffer = await page.screenshot({
    type: "png",
    fullPage: false, // Cuma viewport
  });

  await ctx.close();

  // Composite tagline overlay
  const overlaySvg = createTaglineOverlay(config);
  const outPath = resolve(OUT_DIR, config.file);

  await sharp(screenshotBuffer)
    .composite([{ input: overlaySvg, top: 0, left: 0 }])
    .png({ compressionLevel: 9 })
    .toFile(outPath);

  const stats = await sharp(outPath).metadata();
  console.log(
    `   ✓ Saved: ${config.file}  ${stats.width}×${stats.height}  (${(
      (await sharp(outPath).toBuffer()).length / 1024
    ).toFixed(0)} KB)`,
  );
}

async function main() {
  if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });

  console.log(`📦 Generating App Store screenshots for iPhone 6.7"`);
  console.log(`   Viewport: ${VIEWPORT.width}×${VIEWPORT.height} @ DPR ${DPR}`);
  console.log(`   Output: ${FINAL_WIDTH}×${FINAL_HEIGHT} px`);
  console.log(`   Base URL: ${BASE_URL}`);
  console.log(`   Output dir: ${OUT_DIR}`);

  const browser = await chromium.launch({ headless: true });

  try {
    for (const config of CONFIGS) {
      await generateOne(browser, config);
    }
  } finally {
    await browser.close();
  }

  console.log(`\n✅ Done. Upload PNG di folder ke App Store Connect:`);
  console.log(`   appstoreconnect.apple.com → Natalo Petshop → Distribution`);
  console.log(`   → iOS App 1.0 → Previews and Screenshots → iPhone 6.7"`);
}

main().catch((err) => {
  console.error("❌ Generator failed:", err);
  process.exit(1);
});
