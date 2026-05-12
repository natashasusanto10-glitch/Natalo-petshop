import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { resolve } from "node:path";
import vm from "node:vm";

type ServiceWorkerSandbox = {
  isSensitiveUrl: (url: URL) => boolean;
  isSensitivePageRequest: (request: Request) => boolean;
  shouldCacheResponse: (response: Response) => boolean;
};

function loadServiceWorkerHelpers() {
  const source = readFileSync(resolve("public/sw.template.js"), "utf8");
  const sandbox = {
    URL,
    Response,
    Request,
    Promise,
    self: {
      location: { origin: "https://natalo.test" },
      addEventListener() {},
      skipWaiting() {},
      clients: {
        claim() {},
        matchAll: async () => [],
        openWindow: async () => undefined,
      },
      registration: {
        showNotification: async () => undefined,
      },
    },
  };

  vm.runInNewContext(source, sandbox);
  return sandbox as unknown as ServiceWorkerSandbox;
}

test("service worker treats personal and tokenized pages as sensitive", () => {
  const sw = loadServiceWorkerHelpers();

  assert.equal(sw.isSensitiveUrl(new URL("https://natalo.test/checkout")), true);
  assert.equal(sw.isSensitiveUrl(new URL("https://natalo.test/member/orders")), true);
  assert.equal(sw.isSensitiveUrl(new URL("https://natalo.test/akun/alamat")), true);
  assert.equal(sw.isSensitiveUrl(new URL("https://natalo.test/pesanan/INV-1?token=abc")), true);
  assert.equal(sw.isSensitiveUrl(new URL("https://natalo.test/products/food?token=abc")), true);
  assert.equal(sw.isSensitiveUrl(new URL("https://natalo.test/products/food")), false);
});

test("service worker only caches safe 200 non-private responses", () => {
  const sw = loadServiceWorkerHelpers();

  assert.equal(sw.shouldCacheResponse(new Response("ok", { status: 200 })), true);
  assert.equal(sw.shouldCacheResponse(new Response("missing", { status: 404 })), false);
  assert.equal(
    sw.shouldCacheResponse(
      new Response("private", { headers: { "Cache-Control": "private, max-age=60" } }),
    ),
    false,
  );
  assert.equal(
    sw.shouldCacheResponse(new Response("secret", { headers: { "Cache-Control": "no-store" } })),
    false,
  );
  assert.equal(
    sw.shouldCacheResponse(new Response("stale", { headers: { "Cache-Control": "no-cache" } })),
    false,
  );
});
