import assert from "node:assert/strict";
import test from "node:test";
import {
  isAllowedNlchatOrigin,
  runWithStaffCors,
  staffCorsPreflight,
  withStaffCors,
} from "@/lib/chat/staff-cors";
import { NextResponse } from "next/server";

test("allows official NLCHAT hosting origins and rejects lookalikes", () => {
  assert.equal(isAllowedNlchatOrigin("https://tokochat-a8879.web.app"), true);
  assert.equal(isAllowedNlchatOrigin("https://tokochat-a8879.firebaseapp.com"), true);
  assert.equal(isAllowedNlchatOrigin("https://evil.example"), false);
  assert.equal(isAllowedNlchatOrigin("https://tokochat-a8879.web.app.evil.example"), false);
  assert.equal(isAllowedNlchatOrigin(null), false);
});

test("preflight permits bearer auth from NLCHAT and rejects unknown origins", () => {
  const allowed = staffCorsPreflight(new Request("https://www.natalopetshop.com/api/chat/staff/orders/ORD-1", {
    method: "OPTIONS",
    headers: { Origin: "https://tokochat-a8879.web.app" },
  }));
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get("access-control-allow-origin"), "https://tokochat-a8879.web.app");
  assert.match(allowed.headers.get("access-control-allow-headers") ?? "", /Authorization/);

  const rejected = staffCorsPreflight(new Request("https://www.natalopetshop.com/api/chat/staff/orders/ORD-1", {
    method: "OPTIONS",
    headers: { Origin: "https://evil.example" },
  }));
  assert.equal(rejected.status, 403);
  assert.equal(rejected.headers.get("access-control-allow-origin"), null);
});

test("actual responses expose CORS only to an allowed origin", () => {
  const allowed = withStaffCors(
    new Request("https://www.natalopetshop.com", { headers: { Origin: "https://tokochat-a8879.web.app" } }),
    NextResponse.json({ ok: true }),
  );
  assert.equal(allowed.headers.get("access-control-allow-origin"), "https://tokochat-a8879.web.app");

  const denied = withStaffCors(
    new Request("https://www.natalopetshop.com", { headers: { Origin: "https://evil.example" } }),
    NextResponse.json({ error: "Token wajib." }, { status: 401 }),
  );
  assert.equal(denied.status, 401);
  assert.equal(denied.headers.get("access-control-allow-origin"), null);
});

test("unexpected endpoint failures remain readable by the NLCHAT browser", async () => {
  const request = new Request("https://www.natalopetshop.com", {
    headers: { Origin: "https://tokochat-a8879.web.app" },
  });
  const previous = console.error;
  console.error = () => {};
  try {
    const response = await runWithStaffCors(request, async () => {
      throw new Error("database unavailable");
    });
    assert.equal(response.status, 500);
    assert.equal(response.headers.get("access-control-allow-origin"), "https://tokochat-a8879.web.app");
    assert.deepEqual(await response.json(), { error: "Layanan pesanan sedang tidak tersedia." });
  } finally {
    console.error = previous;
  }
});
