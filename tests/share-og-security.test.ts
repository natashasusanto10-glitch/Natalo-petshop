import assert from "node:assert/strict";
import test from "node:test";

import { fetchSafeOgImageData, safeOgImageUrl } from "@/lib/share/og-image-security";

test("accepts exact and approved CDN suffix HTTPS hosts", () => {
  const previousBunnyHost = process.env.BUNNY_CDN_HOSTNAME;
  process.env.BUNNY_CDN_HOSTNAME = "vz-natalo.b-cdn.net";

  try {
    assert.equal(
      safeOgImageUrl("https://www.natalopetshop.com/brand/logo.png"),
      "https://www.natalopetshop.com/brand/logo.png",
    );
    assert.equal(
      safeOgImageUrl("https://vz-natalo.b-cdn.net/post-1/thumbnail.jpg"),
      "https://vz-natalo.b-cdn.net/post-1/thumbnail.jpg",
    );
    assert.equal(
      safeOgImageUrl("https://image.ufs.sh/f-1/photo.jpg"),
      "https://image.ufs.sh/f-1/photo.jpg",
    );
  } finally {
    if (previousBunnyHost === undefined) delete process.env.BUNNY_CDN_HOSTNAME;
    else process.env.BUNNY_CDN_HOSTNAME = previousBunnyHost;
  }
});

test("rejects deceptive, private, credential, port, fragment, and non-HTTPS URLs", () => {
  for (const value of [
    "https://cdn.natalopetshop.com.evil.test/x.jpg",
    "https://cdn.natalopetshop.com@evil.test/x.jpg",
    "https://user:pass@www.natalopetshop.com/x.jpg",
    "http://www.natalopetshop.com/x.jpg",
    "https://www.natalopetshop.com:444/x.jpg",
    "https://www.natalopetshop.com/x.jpg#fragment",
    "https://127.0.0.1/x.jpg",
    "https://[::1]/x.jpg",
    "https://169.254.169.254/latest/meta-data",
    "https://localhost/x.jpg",
    "https://storage.googleapis.com.example.test/x.jpg",
    "not a URL",
  ]) {
    assert.equal(safeOgImageUrl(value), null, value);
  }
});

test("fetches only bounded image bytes with redirects disabled", async () => {
  const previousBunnyHost = process.env.BUNNY_CDN_HOSTNAME;
  process.env.BUNNY_CDN_HOSTNAME = "vz-natalo.b-cdn.net";
  let request: RequestInit | undefined;

  try {
    const image = await fetchSafeOgImageData(
      "https://vz-natalo.b-cdn.net/post-1/thumbnail.jpg",
      async (_url, init) => {
        request = init;
        return new Response(new Uint8Array([1, 2, 3]), {
          headers: { "content-type": "image/png", "content-length": "3" },
        });
      },
    );

    assert.match(image ?? "", /^data:image\/png;base64,/);
    assert.equal(request?.redirect, "error");
  } finally {
    if (previousBunnyHost === undefined) delete process.env.BUNNY_CDN_HOSTNAME;
    else process.env.BUNNY_CDN_HOSTNAME = previousBunnyHost;
  }
});

test("rejects non-image and oversized remote responses", async () => {
  const previousBunnyHost = process.env.BUNNY_CDN_HOSTNAME;
  process.env.BUNNY_CDN_HOSTNAME = "vz-natalo.b-cdn.net";

  try {
    const source = "https://vz-natalo.b-cdn.net/post-1/thumbnail.jpg";
    assert.equal(
      await fetchSafeOgImageData(source, async () => new Response("nope", {
        headers: { "content-type": "text/html" },
      })),
      null,
    );
    assert.equal(
      await fetchSafeOgImageData(source, async () => new Response("too big", {
        headers: { "content-length": String(5 * 1024 * 1024), "content-type": "image/jpeg" },
      })),
      null,
    );
  } finally {
    if (previousBunnyHost === undefined) delete process.env.BUNNY_CDN_HOSTNAME;
    else process.env.BUNNY_CDN_HOSTNAME = previousBunnyHost;
  }
});
