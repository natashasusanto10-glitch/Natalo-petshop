/**
 * Normalisasi logo brand sebelum disimpan — supaya semua logo punya berat
 * visual yang sama di grid "Brand Favorit" (Home), lepas dari aspect ratio
 * atau padding transparan bawaan file aslinya.
 *
 * Pipeline:
 *   1. Trim border transparan/solid di tepi gambar.
 *   2. Composite logo yang sudah di-trim ke tengah kanvas persegi
 *      transparan, mengisi ~80% kanvas (LOGO_FILL_RATIO).
 *
 * Dipakai bersama oleh:
 * - app/api/admin/upload/route.ts (upload logo baru, kind=brand-logo)
 * - scripts/normalize-brand-logos.mjs (backfill logo lama)
 */
import sharp from "sharp";

const CANVAS_SIZE = 512;
const LOGO_FILL_RATIO = 0.8;

export async function normalizeBrandLogo(input: Buffer): Promise<Buffer> {
  const trimmed = await sharp(input).trim().png().toBuffer();

  const maxLogoDimension = Math.round(CANVAS_SIZE * LOGO_FILL_RATIO);
  const resized = await sharp(trimmed)
    .resize({
      width: maxLogoDimension,
      height: maxLogoDimension,
      fit: "inside",
      // Small logos must enlarge to fill ~80% of canvas (LOGO_FILL_RATIO).
      // With fit: "inside", sharp never upscales beyond the target box
      // regardless of withoutEnlargement, so this must remain false.
      withoutEnlargement: false,
    })
    .png()
    .toBuffer();
  const resizedMeta = await sharp(resized).metadata();

  const resizedWidth = resizedMeta.width ?? maxLogoDimension;
  const resizedHeight = resizedMeta.height ?? maxLogoDimension;
  const left = Math.round((CANVAS_SIZE - resizedWidth) / 2);
  const top = Math.round((CANVAS_SIZE - resizedHeight) / 2);

  return sharp({
    create: {
      width: CANVAS_SIZE,
      height: CANVAS_SIZE,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([{ input: resized, left, top }])
    .png()
    .toBuffer();
}
