import assert from "node:assert/strict";
import test from "node:test";
import sharp from "sharp";
import { normalizeBrandLogo } from "@/lib/upload/normalize-logo";

async function makePngBuffer(options: {
  width: number;
  height: number;
  contentWidth: number;
  contentHeight: number;
}): Promise<Buffer> {
  const { width, height, contentWidth, contentHeight } = options;
  const left = Math.round((width - contentWidth) / 2);
  const top = Math.round((height - contentHeight) / 2);

  const canvas = sharp({
    create: {
      width,
      height,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  });

  const content = await sharp({
    create: {
      width: contentWidth,
      height: contentHeight,
      channels: 4,
      background: { r: 200, g: 30, b: 30, alpha: 255 },
    },
  })
    .png()
    .toBuffer();

  return canvas
    .composite([{ input: content, left, top }])
    .png()
    .toBuffer();
}

test("normalizeBrandLogo produces a square canvas regardless of input aspect ratio", async () => {
  const wideBanner = await makePngBuffer({
    width: 400,
    height: 400,
    contentWidth: 380,
    contentHeight: 60,
  });

  const output = await normalizeBrandLogo(wideBanner);
  const meta = await sharp(output).metadata();

  assert.equal(meta.width, meta.height, "output canvas must be square");
});

test("normalizeBrandLogo trims transparent padding before re-padding", async () => {
  const tinyContentOnBigCanvas = await makePngBuffer({
    width: 500,
    height: 500,
    contentWidth: 50,
    contentHeight: 50,
  });

  const output = await normalizeBrandLogo(tinyContentOnBigCanvas);
  const stats = await sharp(output).clone().extractChannel(3).stats();

  // Setelah trim + re-pad ke ~80% kanvas, opaque pixel harus jauh lebih
  // dominan dibanding versi asli (yang isinya 50x50 di kanvas 500x500 —
  // opaque ratio sangat kecil).
  const opaqueRatio = stats.channels[0].mean / 255;
  assert.ok(
    opaqueRatio > 0.4,
    `expected re-padded logo to fill most of the canvas, got opaque ratio ${opaqueRatio}`,
  );
});

test("normalizeBrandLogo returns a decodable PNG buffer", async () => {
  const input = await makePngBuffer({
    width: 300,
    height: 150,
    contentWidth: 280,
    contentHeight: 40,
  });

  const output = await normalizeBrandLogo(input);
  const meta = await sharp(output).metadata();

  assert.equal(meta.format, "png");
});
