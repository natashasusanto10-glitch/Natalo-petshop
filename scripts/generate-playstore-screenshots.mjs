#!/usr/bin/env node
/**
 * generate-playstore-screenshots.mjs
 *
 * Generate Google Play Store phone screenshots otomatis untuk Natalo Petshop.
 * Pakai Playwright headless Chromium, render halaman produksi dgn viewport
 * Android phone 360×640 × DPR 3 = 1080×1920 native PNG, composite tagline
 * overlay via sharp.
 *
 * Output: screenshots/playstore-phone/01-home.png ... 05-tentang.png
 * Spec Play Store (https://support.google.com/googleplay/android-developer/answer/9866151):
 * - Min 2 screenshots, max 8
 * - 16:9 atau 9:16 aspect ratio recommended
 * - Min side 320 px, max 3840 px
 * - PNG/JPG, max 8 MB
 * - Width/height antara 1:1.78 dan 1.78:1
 *
 * 1080×1920 = portrait 9:16 = sweet spot, kompatibel dgn semua device size.
 *
 * Run:
 *   node scripts/generate-playstore-screenshots.mjs
 *   BASE_URL=https://www.natalopetshop.com node scripts/generate-playstore-screenshots.mjs
 */
import { chromium } from "playwright-core";
import sharp from "sharp";
import { mkdirSync, existsSync, statSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");

const BASE_URL = process.env.BASE_URL || "https://www.natalopetshop.com";

// Android phone reference: Pixel 7 logical 412×915 / DPR ~2.6.
// Untuk Play Store, 360×640 × DPR 3 = 1080×1920 — standar HDPI phone,
// match aspect ratio Play Store 9:16 portrait yang ideal.
const VIEWPORT = { width: 360, height: 640 };
const DPR = 3;
const FINAL_WIDTH = VIEWPORT.width * DPR; // 1080
const FINAL_HEIGHT = VIEWPORT.height * DPR; // 1920

const OUT_DIR = resolve(ROOT, "screenshots/playstore-phone");

const BRAND_BLUE = "#1E5FBF";
const BRAND_BLUE_DARK = "#0F2D5C";

const CONFIGS = [
  {
    file: "01-home.png",
    path: "/",
    tagline: "Belanja Kebutuhan",
    taglineLine2: "Hewan Peliharaan",
    subtagline: "Petshop & aquarium terpercaya di Medan",
  },
  {
    file: "02-products.png",
    path: "/products",
    tagline: "Ribuan Produk",
    taglineLine2: "Brand Original",
    subtagline: "Royal Canin, Whiskas, Pedigree, dan lainnya",
  },
  {
    file: "03-search.png",
    path: "/search",
    tagline: "Cari Produk",
    taglineLine2: "Cepat & Mudah",
    subtagline: "Filter kategori, harga, dan rating real-time",
  },
  {
    file: "04-bantuan.png",
    path: "/bantuan",
    tagline: "Customer Service",
    taglineLine2: "Selalu Siap",
    subtagline: "WhatsApp + email, jam toko Senin-Sabtu",
  },
  {
    file: "05-tentang.png",
    path: "/tentang-kami",
    tagline: "7 Tahun Melayani",
    taglineLine2: "Pet Owner Medan",
    subtagline: "Toko fisik + online store, terpercaya",
  },
];

/**
 * Generate SVG tagline overlay — top 28% screenshot, gradient brand-blue
 * fading to transparent supaya screenshot di bawah masih readable.
 */
function createTaglineOverlay(config) {
  const escape = (s) =>
    s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");

  const main1 = escape(config.tagline);
  const main2 = escape(config.taglineLine2);
  const sub = escape(config.subtagline);

  const overlayHeight = Math.round(FINAL_HEIGHT * 0.26);
  const gradientHeight = Math.round(FINAL_HEIGHT * 0.32);

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
        font-family: "Roboto", "Segoe UI", system-ui, sans-serif;
        font-weight: 900;
        fill: white;
        text-anchor: middle;
        letter-spacing: -0.02em;
      }
      .subtagline {
        font-family: "Roboto", "Segoe UI", system-ui, sans-serif;
        font-weight: 600;
        fill: rgba(255,255,255,0.92);
        text-anchor: middle;
      }
    </style>
  </defs>
  <rect x="0" y="0" width="${FINAL_WIDTH}" height="${gradientHeight}" fill="url(#brand-gradient)"/>
  <text class="tagline" x="${FINAL_WIDTH / 2}" y="${overlayHeight * 0.38}" font-size="92">${main1}</text>
  <text class="tagline" x="${FINAL_WIDTH / 2}" y="${overlayHeight * 0.62}" font-size="92">${main2}</text>
  <text class="subtagline" x="${FINAL_WIDTH / 2}" y="${overlayHeight * 0.85}" font-size="38">${sub}</text>
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
    // Android Chrome user agent — supaya site detect mobile + serve mobile layout
    userAgent:
      "Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    storageState: {
      cookies: [],
      origins: [{ origin: BASE_URL, localStorage: [] }],
    },
  });

  const page = await ctx.newPage();

  // Block analytics/tracking utk loading lebih cepat
  await page.route(/google-analytics|googletagmanager|facebook\.com\/tr|cdn-cgi/, (route) =>
    route.abort(),
  );

  await page.goto(BASE_URL + config.path, {
    waitUntil: "networkidle",
    timeout: 30000,
  });

  // Skip splash animation
  await page.evaluate(() => {
    sessionStorage.setItem("natalo:splash-shown", "1");
  });
  await page.reload({ waitUntil: "networkidle" });

  // Tunggu lazy images + render
  await page.waitForTimeout(2500);

  // Scroll sedikit di halaman dgn hero besar supaya konten relevan visible
  if (config.path === "/" || config.path === "/products") {
    await page.evaluate(() => window.scrollBy({ top: 150, behavior: "instant" }));
    await page.waitForTimeout(700);
  }

  const screenshotBuffer = await page.screenshot({
    type: "png",
    fullPage: false,
  });

  await ctx.close();

  // Composite overlay
  const overlaySvg = createTaglineOverlay(config);
  const outPath = resolve(OUT_DIR, config.file);

  await sharp(screenshotBuffer)
    .composite([{ input: overlaySvg, top: 0, left: 0 }])
    .png({ compressionLevel: 9 })
    .toFile(outPath);

  const stats = await sharp(outPath).metadata();
  const size = statSync(outPath).size;
  console.log(
    `   ✓ Saved: ${config.file}  ${stats.width}×${stats.height}  ${(size / 1024).toFixed(0)} KB`,
  );
}

async function main() {
  if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });

  console.log(`📦 Generating Play Store phone screenshots`);
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

  console.log(`\n✅ Done. Upload PNG di folder ke Play Console:`);
  console.log(`   play.google.com/console → Natalo Petshop → Store presence`);
  console.log(`   → Main store listing → Phone screenshots`);
}

main().catch((err) => {
  console.error("❌ Generator failed:", err);
  process.exit(1);
});
