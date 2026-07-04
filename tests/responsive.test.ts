import test from "node:test";
import assert from "node:assert/strict";
import { gridColsClass } from "../lib/responsive";

test("default columns 2/3/4/5", () => {
  assert.equal(
    gridColsClass(),
    "grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5",
  );
});

test("respects overrides and xxl", () => {
  assert.equal(
    gridColsClass({ base: 2, sm: 2, lg: 4, xl: 5, xxl: 6 }),
    "grid-cols-2 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6",
  );
});

test("omits unset breakpoints", () => {
  assert.equal(gridColsClass({ base: 3 }), "grid-cols-3");
});

test("throws on invalid column count", () => {
  assert.throws(
    () => gridColsClass({ base: 7 }),
    {
      message: /Invalid column count: 7\. Must be one of 2, 3, 4, 5, 6\./,
    },
  );
});
