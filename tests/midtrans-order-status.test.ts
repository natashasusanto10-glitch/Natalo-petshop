import assert from "node:assert/strict";
import test from "node:test";
import { applyMidtransPaidStatus } from "@/lib/midtrans-order-status";

test("late Midtrans PAID callback updates payment without appending PAID history", async () => {
  let historyWrites = 0;
  let updateManyCalls = 0;
  const tx = {
    order: {
      updateMany: async () => {
        updateManyCalls += 1;
        return { count: updateManyCalls === 1 ? 0 : 1 };
      },
      findUniqueOrThrow: async () => ({
        id: "order-1",
        status: "PROCESSING",
        paymentStatus: "PAID",
      }),
    },
    orderStatusHistory: {
      upsert: async () => {
        historyWrites += 1;
        return { id: "history-1" };
      },
    },
  };

  const result = await applyMidtransPaidStatus(
    tx as never,
    { id: "order-1", orderType: "DELIVERY" },
    "settlement",
  );
  assert.equal(result.status, "PROCESSING");
  assert.equal(updateManyCalls, 2);
  assert.equal(historyWrites, 0);
});

test("late Midtrans PAID callback cannot regress a refunded payment", async () => {
  const tx = {
    order: {
      updateMany: async () => ({ count: 0 }),
      findUniqueOrThrow: async () => ({
        id: "order-1",
        status: "REFUNDED",
        paymentStatus: "REFUNDED",
      }),
    },
    orderStatusHistory: {
      upsert: async () => {
        throw new Error("refunded order must not append PAID history");
      },
    },
  };
  const result = await applyMidtransPaidStatus(
    tx as never,
    { id: "order-1", orderType: "DELIVERY" },
    "settlement",
  );
  assert.equal(result.paymentStatus, "REFUNDED");
});
