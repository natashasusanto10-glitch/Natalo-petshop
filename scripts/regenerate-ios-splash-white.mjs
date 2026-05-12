// One-time regenerate iOS Splash.imageset PNGs dengan WHITE background +
// blue NL logo (kebalikan dari versi lama yang full blue).
//
// Background: sebelumnya splash full biru (#1E5FBF) bikin status bar zone
// di iOS terlihat biru saat splash/transition. Sekarang: bg PUTIH dengan
// logo biru di tengah supaya status bar safe-area tidak tinted biru.
//
// Run: node scripts/regenerate-ios-splash-white.mjs
//
// Output: replace
//   ios/App/App/Assets.xcassets/Splash.imageset/Default@{1,2,3}x~universal~anyany{,-dark}.png

import sharp from "sharp";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");

const SOURCE_LOGO = resolve(ROOT, "public/icons/icon-512x512.png");
const SPLASH_DIR = resolve(ROOT, "ios/App/App/Assets.xcassets/Splash.imageset");

// Canvas standar Capacitor: 2732x2732. iOS scale generated:
//   @1x = 2732/3 = ~910 (Capacitor pakai full canvas untuk @1x juga)
//   @2x = 2732 (same)
//   @3x = 2732 (same)
// Capacitor-assets output semua di 2732x2732 untuk simplicity.
const CANVAS = 2732;
const LOGO_SIZE = 600; // Logo di tengah, ~22% canvas

async function generateSplash(outputPath) {
  // Resize logo ke LOGO_SIZE x LOGO_SIZE
  const logoBuffer = await sharp(SOURCE_LOGO)
    .resize(LOGO_SIZE, LOGO_SIZE, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .toBuffer();

  // White canvas + composite logo di tengah
  await sharp({
    create: {
      width: CANVAS,
      height: CANVAS,
      channels: 4,
      background: { r: 255, g: 255, b: 255, alpha: 1 }, // #ffffff
    },
  })
    .composite([
      {
        input: logoBuffer,
        gravity: "center",
      },
    ])
    .png()
    .toFile(outputPath);

  console.log(`✓ ${outputPath}`);
}

async function main() {
  const files = [
    "Default@1x~universal~anyany.png",
    "Default@2x~universal~anyany.png",
    "Default@3x~universal~anyany.png",
    "Default@1x~universal~anyany-dark.png",
    "Default@2x~universal~anyany-dark.png",
    "Default@3x~universal~anyany-dark.png",
  ];

  for (const filename of files) {
    await generateSplash(resolve(SPLASH_DIR, filename));
  }

  console.log("\n✅ Splash.imageset regenerated dengan WHITE background.");
  console.log("Next steps:");
  console.log("  1. npm run cap:sync:ios");
  console.log("  2. Open ios/App/App.xcworkspace di Xcode");
  console.log("  3. Build + upload new TestFlight");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
