import assert from "node:assert/strict";
import { test } from "node:test";

import sharp from "sharp";

import { toJpegOgResponse } from "@/lib/share/og/jpeg-response";

test("toJpegOgResponse: PNG besar -> JPEG jauh lebih kecil, header cache ikut", async () => {
  // Noise acak = konten fotografis terburuk untuk PNG; meniru kartu produk
  // 2,6 MB yang dibuang WhatsApp.
  const { randomBytes } = await import("node:crypto");
  const raw = randomBytes(600 * 600 * 3);
  const png = await sharp(raw, { raw: { width: 600, height: 600, channels: 3 } })
    .png()
    .toBuffer();

  const res = await toJpegOgResponse(
    new Response(new Uint8Array(png), { headers: { "content-type": "image/png" } }),
    { "Cache-Control": "public, s-maxage=3600" },
  );

  assert.equal(res.headers.get("content-type"), "image/jpeg");
  assert.equal(res.headers.get("cache-control"), "public, s-maxage=3600");
  const body = Buffer.from(await res.arrayBuffer());
  assert.ok(body.length > 0);
  assert.ok(body.length < png.length / 2, `jpeg ${body.length}B vs png ${png.length}B`);
  // Magic bytes JPEG.
  assert.equal(body[0], 0xff);
  assert.equal(body[1], 0xd8);
});

test("toJpegOgResponse: alpha transparan di-flatten jadi putih, bukan hitam", async () => {
  const png = await sharp({
    create: { width: 8, height: 8, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  })
    .png()
    .toBuffer();

  const res = await toJpegOgResponse(new Response(new Uint8Array(png)), {});
  const body = Buffer.from(await res.arrayBuffer());
  const { data } = await sharp(body).raw().toBuffer({ resolveWithObject: true });
  assert.ok(data[0] > 240 && data[1] > 240 && data[2] > 240, `pixel ${data[0]},${data[1]},${data[2]}`);
});
