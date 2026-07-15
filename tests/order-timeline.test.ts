import assert from "node:assert/strict";
import test from "node:test";
import { serializeOrderDetail } from "@/lib/order-detail";

function serialize(events: Array<Record<string, unknown>>) {
  return serializeOrderDetail({
    id: "order-1",
    orderNumber: "ORDER-1",
    status: "DELIVERED",
    orderType: "DELIVERY",
    items: [],
    voucherUsages: [],
    timelineEvents: events,
    createdAt: new Date("2026-07-15T00:00:00.000Z"),
    updatedAt: new Date("2026-07-16T00:00:00.000Z"),
  } as any);
}

test("serializes canonical pickup lifecycle timestamps", () => {
  const result = serialize([
    { id: "1", status: "PAID", occurredAt: new Date("2026-07-15T01:00:00Z"), actorType: "ADMIN" },
    { id: "2", status: "PROCESSING", occurredAt: new Date("2026-07-15T01:00:00Z"), actorType: "ADMIN" },
    { id: "3", status: "READY_FOR_PICKUP", occurredAt: new Date("2026-07-15T03:00:00Z"), actorType: "ADMIN" },
    { id: "4", status: "DELIVERED", occurredAt: new Date("2026-07-15T05:00:00Z"), actorType: "ADMIN" },
  ]);
  assert.deepEqual(result.timelineEvents.map((event) => event.status), [
    "PAID", "PROCESSING", "READY_FOR_PICKUP", "DELIVERED",
  ]);
});

test("serializes canonical delivery lifecycle timestamps", () => {
  const result = serialize([
    { id: "1", status: "PENDING", occurredAt: new Date("2026-07-15T00:00:00Z"), actorType: "CUSTOMER" },
    { id: "2", status: "PAID", occurredAt: new Date("2026-07-15T01:00:00Z"), actorType: "PAYMENT_PROVIDER" },
    { id: "3", status: "PROCESSING", occurredAt: new Date("2026-07-15T02:00:00Z"), actorType: "ADMIN" },
    { id: "4", status: "SHIPPED", occurredAt: new Date("2026-07-15T04:00:00Z"), actorType: "ADMIN" },
    { id: "5", status: "DELIVERED", occurredAt: new Date("2026-07-16T04:00:00Z"), actorType: "CUSTOMER" },
  ]);
  assert.deepEqual(result.timelineEvents.map((event) => event.status), [
    "PENDING", "PAID", "PROCESSING", "SHIPPED", "DELIVERED",
  ]);
});

test("does not invent timeline timestamps for legacy orders", () => {
  assert.deepEqual(serialize([]).timelineEvents, []);
});
