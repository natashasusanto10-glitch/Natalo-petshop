import assert from "node:assert/strict";
import test from "node:test";

import {
  fetchSafeOgImageData,
  MAX_OG_IMAGE_BYTES,
  resolveOgImageCachePolicy,
  safeOgImageUrl,
} from "@/lib/share/og-image-security";

const nataloImageUrl = "https://www.natalopetshop.com/assets/images/preview.png";
const pngBytes = new Uint8Array([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
]);

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

test("allows only static image paths on Natalo hosts and rejects recursive route bypasses", () => {
  assert.equal(safeOgImageUrl(nataloImageUrl), nataloImageUrl);
  assert.equal(
    safeOgImageUrl("https://www.natalopetshop.com/uploads/member/avatar.webp"),
    "https://www.natalopetshop.com/uploads/member/avatar.webp",
  );

  for (const value of [
    "https://www.natalopetshop.com/api/share/og/feed/post-1?v=token",
    "https://www.natalopetshop.com/%61pi/share/og/feed/post-1",
    "https://www.natalopetshop.com/assets/../api/share/og/feed/post-1",
    "https://www.natalopetshop.com/assets/%2e%2e%2fapi/share/og/feed/post-1.png",
    "https://www.natalopetshop.com/feed/post-1",
    "https://www.natalopetshop.com/_next/image?url=https%3A%2F%2Fevil.test%2Fx.png",
    "https://www.natalopetshop.com/assets/images/preview.svg",
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
        return new Response(pngBytes, {
          headers: { "content-type": "image/png", "content-length": String(pngBytes.byteLength) },
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

test("cancels and aborts streaming payloads above 4 MB even without or with lying Content-Length", async () => {
  for (const contentLength of [null, "8"]) {
    let cancelled = false;
    let aborted = false;
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(pngBytes);
        controller.enqueue(new Uint8Array(MAX_OG_IMAGE_BYTES));
      },
      cancel() {
        cancelled = true;
      },
    });

    const image = await fetchSafeOgImageData(nataloImageUrl, async (_url, init) => {
      init?.signal?.addEventListener("abort", () => {
        aborted = true;
      });
      return new Response(stream, {
        headers: {
          "content-type": "image/png",
          ...(contentLength ? { "content-length": contentLength } : {}),
        },
      });
    });

    assert.equal(image, null, `content-length=${contentLength ?? "absent"}`);
    assert.equal(cancelled, true, `reader cancels content-length=${contentLength ?? "absent"}`);
    assert.equal(aborted, true, `fetch aborts content-length=${contentLength ?? "absent"}`);
  }
});

test("rejects forged image MIME values unless matching raster magic bytes", async () => {
  for (const [name, bytes] of [
    ["HTML", new TextEncoder().encode("<html>not an image</html>")],
    ["SVG", new TextEncoder().encode("<svg xmlns=\"http://www.w3.org/2000/svg\" />")],
    ["corrupt", new Uint8Array([1, 2, 3, 4])],
    ["truncated PNG", new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])],
  ] as const) {
    assert.equal(
      await fetchSafeOgImageData(
        nataloImageUrl,
        async () => new Response(bytes, { headers: { "content-type": "image/png" } }),
      ),
      null,
      name,
    );
  }

  assert.equal(
    await fetchSafeOgImageData(
      nataloImageUrl,
      async () => new Response(new Uint8Array([0xff, 0xd8, 0xff, 0xff, 0xd9]), {
        headers: { "content-type": "image/png" },
      }),
    ),
    null,
    "mismatched JPEG bytes",
  );

  for (const [contentType, bytes] of [
    ["image/jpeg", new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0xff, 0xd9])],
    ["image/png", pngBytes],
    ["image/webp", new Uint8Array([0x52, 0x49, 0x46, 0x46, 0x0c, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x20, 0, 0, 0, 0])],
    ["image/gif", new TextEncoder().encode("GIF89a;")],
  ] as const) {
    const image = await fetchSafeOgImageData(
      nataloImageUrl,
      async () => new Response(bytes, { headers: { "content-type": contentType } }),
    );
    assert.match(image ?? "", new RegExp(`^data:${contentType};base64,`));
  }
});

test("only current OG version is cacheable and other v values never create cache entries", () => {
  const current = "CurrentPreview_1";

  assert.deepEqual(resolveOgImageCachePolicy(current, current), {
    cacheControl: "public, s-maxage=3600, stale-while-revalidate=86400",
    redirectToVersion: null,
  });
  assert.deepEqual(resolveOgImageCachePolicy(null, current), {
    cacheControl: "private, no-store",
    redirectToVersion: null,
  });

  for (const requested of ["random-token", "<script>", "x".repeat(1_000)]) {
    assert.deepEqual(resolveOgImageCachePolicy(requested, current), {
      cacheControl: "private, no-store",
      redirectToVersion: current,
    });
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
