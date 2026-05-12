#!/usr/bin/env node
/**
 * generate-playstore-graphic.mjs
 *
 * Generate Google Play Store feature graphic 1024×500 PNG.
 * Compose: Natalo brand gradient + horizontal logo + tagline +
 * subtle paw-print pattern di kanan.
 *
 * Output: natalo-petshop-app/dist/play-store-feature-graphic.png
 *
 * Specs Play Store (https://support.google.com/googleplay/android-developer/answer/9866151):
 * - 1024 × 500 px, PNG/JPG, max 1 MB, RGB (no transparency)
 * - Aman zone: keep critical content dalam center area
 *   (sides bisa di-crop di beberapa screen sizes)
 */
import sharp from "sharp";
import { readFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const ICON_PATH = resolve(ROOT, "natalo-petshop-app/resources/icon.png"); // 1024×1024, alpha
const OUTPUT = resolve(ROOT, "natalo-petshop-app/dist/play-store-feature-graphic.png");

const W = 1024;
const H = 500;

// Natalo brand colors
const BLUE_PRIMARY = "#1E5FBF";
const BLUE_DARK = "#143E7E";
const WHITE = "#FFFFFF";
const WHITE_SOFT = "rgba(255,255,255,0.85)";

// SVG background: gradient + decorative paw circles di kanan
const bgSvg = `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${BLUE_PRIMARY}" />
      <stop offset="100%" stop-color="${BLUE_DARK}" />
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="rgba(255,255,255,0.18)" />
      <stop offset="100%" stop-color="rgba(255,255,255,0)" />
    </radialGradient>
    <!-- Soft drop shadow utk icon supaya keluar dari background -->
    <filter id="iconShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="8"/>
      <feOffset dx="0" dy="4" result="offsetblur"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.3"/></feComponentTransfer>
      <feMerge>
        <feMergeNode/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#g)" />

  <!-- Decorative glow di kanan, kasih depth -->
  <ellipse cx="850" cy="250" rx="260" ry="280" fill="url(#glow)" />

  <!-- Paw print stylized pattern di kanan, opacity rendah -->
  <g opacity="0.13" fill="${WHITE}">
    <!-- Big paw -->
    <ellipse cx="900" cy="155" rx="42" ry="55" />
    <ellipse cx="835" cy="120" rx="22" ry="28" />
    <ellipse cx="880" cy="85" rx="22" ry="28" />
    <ellipse cx="935" cy="85" rx="22" ry="28" />
    <ellipse cx="975" cy="120" rx="22" ry="28" />

    <!-- Medium paw -->
    <ellipse cx="940" cy="395" rx="28" ry="36" />
    <ellipse cx="900" cy="373" rx="14" ry="18" />
    <ellipse cx="928" cy="350" rx="14" ry="18" />
    <ellipse cx="962" cy="350" rx="14" ry="18" />
    <ellipse cx="985" cy="373" rx="14" ry="18" />
  </g>
</svg>`;

// SVG text overlay — wordmark "Natalo Petshop" + tagline + badge
const textSvg = `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
  <style>
    .brand   { font-family: 'Segoe UI', 'Inter', system-ui, sans-serif;
               font-weight: 900; font-size: 70px; fill: ${WHITE};
               letter-spacing: -1.5px; }
    .brandsub{ font-family: 'Segoe UI', 'Inter', system-ui, sans-serif;
               font-weight: 700; font-size: 18px; fill: ${WHITE_SOFT};
               letter-spacing: 4px; }
    .tagline { font-family: 'Segoe UI', 'Inter', system-ui, sans-serif;
               font-weight: 700; font-size: 32px; fill: ${WHITE}; }
    .sub     { font-family: 'Segoe UI', 'Inter', system-ui, sans-serif;
               font-weight: 600; font-size: 20px; fill: ${WHITE_SOFT}; }
    .badge   { font-family: 'Segoe UI', 'Inter', system-ui, sans-serif;
               font-weight: 700; font-size: 15px; fill: ${BLUE_DARK};
               letter-spacing: 1px; }
  </style>

  <!-- Brand wordmark — di sebelah kanan icon, posisi top -->
  <text x="280" y="148" class="brand">Natalo</text>
  <text x="282" y="178" class="brandsub">PETSHOP</text>

  <!-- Tagline utama -->
  <text x="80" y="290" class="tagline">Pakan &amp; kebutuhan hewan</text>
  <text x="80" y="332" class="tagline">peliharaan, antar sehari.</text>

  <!-- Sub-tagline -->
  <text x="80" y="378" class="sub">Belanja online · Antar ke seluruh Medan</text>

  <!-- Badge "PETSHOP TERPERCAYA" -->
  <g transform="translate(80, 410)">
    <rect x="0" y="0" width="225" height="36" rx="18" fill="${WHITE}" />
    <text x="113" y="24" class="badge" text-anchor="middle">★ PETSHOP TERPERCAYA</text>
  </g>
</svg>`;

async function main() {
  mkdirSync(dirname(OUTPUT), { recursive: true });

  // App icon: resize 200×200, keep alpha, add subtle shadow via composite
  const iconBuf = await sharp(ICON_PATH)
    .resize(200, 200, { fit: "contain" })
    .toBuffer();

  // Compose: background → icon (kiri-atas) → text (wordmark di kanan icon + tagline di bawah)
  await sharp(Buffer.from(bgSvg))
    .composite([
      { input: iconBuf, left: 70, top: 70 },
      { input: Buffer.from(textSvg) },
    ])
    .png({ compressionLevel: 9 })
    .toFile(OUTPUT);

  const stats = await sharp(OUTPUT).metadata();
  const fileSize = (await import("node:fs")).statSync(OUTPUT).size;
  console.log(`[playstore-graphic] ✓ Generated:`);
  console.log(`  ${OUTPUT}`);
  console.log(`  ${stats.width}×${stats.height} ${stats.format}, ${(fileSize / 1024).toFixed(1)} KB`);
}

main().catch((err) => {
  console.error("[playstore-graphic] ❌ Failed:", err);
  process.exit(1);
});
