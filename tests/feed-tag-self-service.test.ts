import test from "node:test";
import assert from "node:assert/strict";
import { parseHiddenBody } from "../lib/feed/tagged-users";

test("parseHiddenBody: hanya boolean yang valid", () => {
  assert.deepEqual(parseHiddenBody({ hidden: true }), { ok: true, hidden: true });
  assert.deepEqual(parseHiddenBody({ hidden: false }), { ok: true, hidden: false });
  assert.equal(parseHiddenBody({ hidden: "true" }).ok, false);
  assert.equal(parseHiddenBody({}).ok, false);
  assert.equal(parseHiddenBody(null).ok, false);
});
