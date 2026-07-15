import assert from "node:assert/strict";
import test from "node:test";
import { recordOrderStatusEvent } from "@/lib/order-transitions";

test("status event idempotency key prevents duplicate callback history", async () => {
  const records = new Map<string, { id: string }>();
  let createCount = 0;
  const tx = {
    orderStatusHistory: {
      upsert: async ({ where }: { where: { idempotencyKey: string } }) => {
        const existing = records.get(where.idempotencyKey);
        if (existing) return existing;
        createCount += 1;
        const record = { id: `event-${createCount}` };
        records.set(where.idempotencyKey, record);
        return record;
      },
      create: async ({ data }: { data: { idempotencyKey?: string } }) => {
        createCount += 1;
        const record = { id: `event-${createCount}` };
        if (data.idempotencyKey) records.set(data.idempotencyKey, record);
        return record;
      },
    },
  };

  const context = {
    actorType: "PAYMENT_PROVIDER" as const,
    actorId: "MIDTRANS",
    idempotencyKey: "midtrans:order-1:paid",
  };
  const first = await recordOrderStatusEvent(
    tx as never,
    "order-1",
    "PAID",
    context
  );
  const retry = await recordOrderStatusEvent(
    tx as never,
    "order-1",
    "PAID",
    context
  );

  assert.equal(createCount, 1);
  assert.deepEqual(retry, first);
});
