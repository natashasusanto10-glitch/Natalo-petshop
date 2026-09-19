import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import { assertCronAuth } from "@/lib/cron-auth";

// assertCronAuth baca process.env.CRON_SECRET per call — helper ini
// set/restore env di sekitar tiap assertion supaya test tidak saling
// bocor state.
function withCronSecret(value: string | undefined, fn: () => void): void {
  const prev = process.env.CRON_SECRET;
  if (value === undefined) {
    delete process.env.CRON_SECRET;
  } else {
    process.env.CRON_SECRET = value;
  }
  try {
    fn();
  } finally {
    if (prev === undefined) {
      delete process.env.CRON_SECRET;
    } else {
      process.env.CRON_SECRET = prev;
    }
  }
}

function requestWithAuth(header?: string): Request {
  return new Request("https://natalo.test/api/cron/test", {
    headers: header === undefined ? {} : { authorization: header },
  });
}

describe("assertCronAuth", () => {
  afterEach(() => {
    delete process.env.CRON_SECRET;
  });

  it("lolos (null) saat secret ter-set dan header cocok", () => {
    withCronSecret("s3cr3t-token", () => {
      assert.equal(assertCronAuth(requestWithAuth("Bearer s3cr3t-token")), null);
    });
  });

  it("tolak 403 saat CRON_SECRET tidak ter-set (fail-closed)", () => {
    withCronSecret(undefined, () => {
      const res = assertCronAuth(requestWithAuth("Bearer s3cr3t-token"));
      assert.equal(res?.status, 403);
    });
  });

  it("tolak 403 saat header salah", () => {
    withCronSecret("s3cr3t-token", () => {
      const res = assertCronAuth(requestWithAuth("Bearer salah"));
      assert.equal(res?.status, 403);
    });
  });

  it("tolak 403 saat header authorization tidak ada", () => {
    withCronSecret("s3cr3t-token", () => {
      const res = assertCronAuth(requestWithAuth());
      assert.equal(res?.status, 403);
    });
  });
});
