import { NextResponse } from "next/server";
import sharp from "sharp";

/**
 * WhatsApp membuang og:image yang lebih besar dari ±600 KB — preview jatuh
 * ke teks-saja tanpa error. Kanvas foto 1200x1200 sebagai PNG rutin tembus
 * 2 MB (foto fotografis tidak cocok dikompresi PNG), jadi hasil ImageResponse
 * WAJIB dire-encode ke JPEG sebelum dikirim. Kualitas 82 + mozjpeg menahan
 * kartu foto penuh di kisaran 100-250 KB tanpa artefak terlihat di ukuran
 * preview chat.
 */
const OG_JPEG_QUALITY = 82;

export async function toJpegOgResponse(
  image: Response,
  headers: Record<string, string>,
): Promise<NextResponse> {
  const png = Buffer.from(await image.arrayBuffer());
  try {
    const jpeg = await sharp(png)
      // Kanvas kartu selalu berlatar putih; flatten menjaga area transparan
      // (foto contain non-1:1) tetap putih, bukan hitam default JPEG.
      .flatten({ background: "#FFFFFF" })
      .jpeg({ quality: OG_JPEG_QUALITY, mozjpeg: true })
      .toBuffer();
    return new NextResponse(new Uint8Array(jpeg), {
      headers: {
        ...headers,
        "Content-Type": "image/jpeg",
        "Content-Length": String(jpeg.byteLength),
      },
    });
  } catch {
    // sharp gagal (biner native tidak termuat, dsb) — kirim PNG apa adanya;
    // kartu besar yang kadang dibuang WhatsApp tetap lebih baik daripada 500.
    return new NextResponse(new Uint8Array(png), {
      headers: {
        ...headers,
        "Content-Type": "image/png",
        "Content-Length": String(png.byteLength),
      },
    });
  }
}
