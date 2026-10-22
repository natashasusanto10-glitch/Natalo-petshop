import assert from "node:assert/strict";
import test from "node:test";
import {
  buildCustomerSnapshot,
  upsertOrderContextMessage,
  writeOrderReviewNotice,
  writeCustomerMessage,
  type FirestoreLike,
  type CollectionRefLike,
  type DocRefLike,
  type QueryLike,
  type QuerySnapshotLike,
  type DocSnapshotLike,
  type TransactionLike,
} from "@/lib/chat/rooms";
import {
  buildOrderContextRefreshPayload,
  deliverOrderContextPayload,
  type OrderRefreshSource,
} from "@/lib/chat/order-outbox";

// ---------------------------------------------------------------------------
// Fake Firestore Admin SDK minimal — in-memory, keyed by full doc path
// (mis. "customerChats/cust_u1" atau "customerChats/cust_u1/messages/auto1").
// Mengimplementasikan subset yang dipakai writeCustomerMessage:
//   collection(name).doc(id?) / .where(field, op, value).limit(n).get()
//   runTransaction(fn) -> tx.get(docRef) / tx.set(docRef, data, {merge})
// ---------------------------------------------------------------------------
function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v) &&
    Object.getPrototypeOf(v) === Object.prototype;
}

// Meniru merge-set Firestore asli: peta bertingkat digabung dalam, array/nilai lain diganti.
function deepMerge(a: Record<string, unknown>, b: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...a };
  for (const [k, v] of Object.entries(b)) {
    out[k] = isPlainObject(v) && isPlainObject(out[k]) ? deepMerge(out[k] as Record<string, unknown>, v) : v;
  }
  return out;
}

function makeFakeFirestore(store: Map<string, Record<string, unknown>>): FirestoreLike {
  let autoIdCounter = 0;
  const nextAutoId = () => `auto${++autoIdCounter}`;

  function makeDocRef(path: string): DocRefLike {
    const segments = path.split("/");
    return {
      id: segments[segments.length - 1],
      path,
      collection(name: string): CollectionRefLike {
        return makeCollectionRef(`${path}/${name}`);
      },
    };
  }

  function directChildDocs(collectionPath: string): Array<{ id: string; data: Record<string, unknown> }> {
    const prefix = `${collectionPath}/`;
    const out: Array<{ id: string; data: Record<string, unknown> }> = [];
    for (const [key, value] of store.entries()) {
      if (!key.startsWith(prefix)) continue;
      const rest = key.slice(prefix.length);
      if (rest.includes("/")) continue; // hanya dokumen langsung, bukan sub-subcollection
      out.push({ id: rest, data: value });
    }
    return out;
  }

  function makeQuery(
    collectionPath: string,
    filters: Array<{ field: string; value: unknown }>,
  ): QueryLike {
    const query: QueryLike = {
      limit() {
        return query; // no-op cukup untuk kontrak test ini
      },
      async get(): Promise<QuerySnapshotLike> {
        const docs = directChildDocs(collectionPath).filter((d) =>
          filters.every((f) => d.data[f.field] === f.value),
        );
        const snaps: DocSnapshotLike[] = docs.map((d) => ({
          id: d.id,
          exists: true,
          data: () => d.data,
        }));
        return { empty: snaps.length === 0, docs: snaps };
      },
    };
    return query;
  }

  function makeCollectionRef(path: string): CollectionRefLike {
    return {
      doc(id?: string): DocRefLike {
        return makeDocRef(`${path}/${id ?? nextAutoId()}`);
      },
      where(field: string, _op: "==", value: unknown): QueryLike {
        return makeQuery(path, [{ field, value }]);
      },
    };
  }

  return {
    collection(name: string): CollectionRefLike {
      return makeCollectionRef(name);
    },
    async runTransaction<T>(fn: (tx: TransactionLike) => Promise<T>): Promise<T> {
      const tx: TransactionLike = {
        async get(ref: DocRefLike): Promise<DocSnapshotLike> {
          const data = store.get(ref.path);
          return { id: ref.id, exists: data !== undefined, data: () => data };
        },
        set(ref: DocRefLike, data: Record<string, unknown>, options?: { merge?: boolean }) {
          if (options?.merge) {
            const existing = store.get(ref.path) ?? {};
            store.set(ref.path, deepMerge(existing, data));
          } else {
            store.set(ref.path, { ...data });
          }
        },
      };
      return fn(tx);
    },
  };
}

test("buildCustomerSnapshot merangkum user + agregat order", () => {
  const snap = buildCustomerSnapshot(
    { name: "Andi", phone: "0812" },
    { totalBelanja: 500000, orderCount: 3, lastOrder: { inv: "INV-9", status: "PAID", total: 150000 } },
  );
  assert.equal(snap.customerName, "Andi");
  assert.equal(snap.customerPhone, "0812");
  assert.equal(snap.summary.totalBelanja, 500000);
  assert.equal(snap.summary.lastOrder?.inv, "INV-9");
  assert.equal(typeof snap.summaryUpdatedAt, "number");
});

test("writeCustomerMessage idempoten via clientMsgId", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const fakeFirestore = makeFakeFirestore(store);
  const deps = { firestore: fakeFirestore, now: () => 1000 };
  const input = {
    chatId: "cust_u1", customerId: "u1", senderRole: "customer" as const, senderId: "u1",
    senderName: "Andi", type: "text" as const, text: "halo", clientMsgId: "abcd1234",
  };

  const first = await writeCustomerMessage(deps, input);
  const second = await writeCustomerMessage(deps, input); // retry sama

  assert.equal(second.deduped, true);
  assert.equal(first.deduped, false);
  assert.equal(first.messageId, second.messageId); // tak buat pesan dobel

  // Tak ada dokumen pesan duplikat di store (satu clientMsgId -> satu doc).
  const messageDocs = [...store.keys()].filter((k) => k.startsWith("customerChats/cust_u1/messages/"));
  assert.equal(messageDocs.length, 1);
});

test("writeCustomerMessage: room hasil merge punya customerId (fix B2)", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const fakeFirestore = makeFakeFirestore(store);
  const deps = { firestore: fakeFirestore, now: () => 2000 };
  const input = {
    chatId: "cust_u2", customerId: "u2", senderRole: "customer" as const, senderId: "u2",
    senderName: "Budi", type: "text" as const, text: "test", clientMsgId: "efgh5678",
  };

  await writeCustomerMessage(deps, input);

  const room = store.get("customerChats/cust_u2");
  assert.ok(room, "room doc harus dibuat");
  assert.equal(room?.customerId, "u2");
  assert.equal(room?.createdAt, 2000);
  assert.equal(room?.updatedAt, 2000);
  assert.equal(room?.lastMessageText, "test");
  assert.equal(room?.lastMessageSender, "customer");
  // Unread BUKAN tanggung jawab proxy — tak boleh disentuh writeCustomerMessage.
  assert.equal(room?.unreadCount, undefined);
  assert.equal(room?.unreadForCustomer, undefined);
});

test("writeCustomerMessage: createdAt room hanya diset bila absen (tak ditimpa saat pesan kedua)", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const fakeFirestore = makeFakeFirestore(store);
  const deps = { firestore: fakeFirestore, now: () => 3000 };
  const input1 = {
    chatId: "cust_u3", customerId: "u3", senderRole: "customer" as const, senderId: "u3",
    senderName: "Citra", type: "text" as const, text: "pesan 1", clientMsgId: "msg-1",
  };
  await writeCustomerMessage(deps, input1);

  const deps2 = { firestore: fakeFirestore, now: () => 4000 };
  const input2 = {
    chatId: "cust_u3", customerId: "u3", senderRole: "customer" as const, senderId: "u3",
    senderName: "Citra", type: "text" as const, text: "pesan 2", clientMsgId: "msg-2",
  };
  await writeCustomerMessage(deps2, input2);

  const room = store.get("customerChats/cust_u3");
  assert.equal(room?.createdAt, 3000); // tak berubah
  assert.equal(room?.updatedAt, 4000); // terbaru
  assert.equal(room?.lastMessageText, "pesan 2");

  const messageDocs = [...store.keys()].filter((k) => k.startsWith("customerChats/cust_u3/messages/"));
  assert.equal(messageDocs.length, 2);
});

test("writeCustomerMessage menulis dokumen pesan dgn bentuk benar", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const fakeFirestore = makeFakeFirestore(store);
  const deps = { firestore: fakeFirestore, now: () => 5000 };
  const input = {
    chatId: "cust_u4", customerId: "u4", senderRole: "customer" as const, senderId: "u4",
    senderName: "Dedi", type: "text" as const, text: "halo min", clientMsgId: "shape-1",
  };

  const result = await writeCustomerMessage(deps, input);

  const messageKey = [...store.keys()].find((k) => k.startsWith("customerChats/cust_u4/messages/"));
  assert.ok(messageKey, "dokumen pesan harus dibuat");
  const messageDoc = store.get(messageKey!);
  assert.ok(messageDoc, "dokumen pesan harus terbaca dari store");

  assert.equal(messageKey, `customerChats/cust_u4/messages/${result.messageId}`);
  assert.equal(messageDoc?.clientMsgId, "shape-1");
  assert.equal(messageDoc?.senderRole, "customer");
  assert.equal(messageDoc?.senderId, "u4");
  assert.equal(messageDoc?.senderName, "Dedi");
  assert.equal(messageDoc?.type, "text");
  assert.equal(messageDoc?.text, "halo min");
  assert.equal(typeof messageDoc?.createdAt, "number");
  assert.equal(messageDoc?.createdAt, 5000);
  assert.equal(messageDoc?.status, "sent");
});

// ---------------------------------------------------------------------------
// F4 fix: room BARU harus distempel `status` awal, else Firestore whereIn
// query inbox staf (`where('status', whereIn: [...])`) tak pernah match
// dokumen tanpa field `status` — room customer baru invisible di inbox.
// ---------------------------------------------------------------------------

test("writeCustomerMessage: room BARU distempel status waiting_staff (F4 — tanpa ini room invisible di inbox staf)", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const fakeFirestore = makeFakeFirestore(store);
  const deps = { firestore: fakeFirestore, now: () => 6000 };
  const input = {
    chatId: "cust_u5", customerId: "u5", senderRole: "customer" as const, senderId: "u5",
    senderName: "Eka", type: "text" as const, text: "halo min", clientMsgId: "status-1",
  };

  await writeCustomerMessage(deps, input);

  const room = store.get("customerChats/cust_u5");
  assert.equal(room?.status, "waiting_staff");
  assert.equal(room?.statusChangedAt, 6000);
  assert.equal(room?.statusChangedBy, "system");
});

test("writeCustomerMessage: room existing berstatus resolved TIDAK ditimpa (transisi tetap milik auto-reopen)", async () => {
  const store = new Map<string, Record<string, unknown>>();
  store.set("customerChats/cust_u6", {
    customerId: "u6",
    status: "resolved",
    statusChangedAt: 1000,
    statusChangedBy: "staff-1",
    createdAt: 1000,
    updatedAt: 1000,
  });
  const fakeFirestore = makeFakeFirestore(store);
  const deps = { firestore: fakeFirestore, now: () => 7000 };
  const input = {
    chatId: "cust_u6", customerId: "u6", senderRole: "customer" as const, senderId: "u6",
    senderName: "Fajar", type: "text" as const, text: "masih ada?", clientMsgId: "status-2",
  };

  await writeCustomerMessage(deps, input);

  const room = store.get("customerChats/cust_u6");
  assert.equal(room?.status, "resolved"); // tak ditimpa — reopen adalah tanggung jawab auto-effects
  assert.equal(room?.statusChangedAt, 1000);
  assert.equal(room?.statusChangedBy, "staff-1");
});

test("writeCustomerMessage: room existing berstatus waiting_customer TIDAK ditimpa", async () => {
  const store = new Map<string, Record<string, unknown>>();
  store.set("customerChats/cust_u7", {
    customerId: "u7",
    status: "waiting_customer",
    statusChangedAt: 2000,
    statusChangedBy: "staff-2",
    createdAt: 2000,
    updatedAt: 2000,
  });
  const fakeFirestore = makeFakeFirestore(store);
  const deps = { firestore: fakeFirestore, now: () => 8000 };
  const input = {
    chatId: "cust_u7", customerId: "u7", senderRole: "customer" as const, senderId: "u7",
    senderName: "Gita", type: "text" as const, text: "oke siap", clientMsgId: "status-3",
  };

  await writeCustomerMessage(deps, input);

  const room = store.get("customerChats/cust_u7");
  assert.equal(room?.status, "waiting_customer"); // tak berubah
  assert.equal(room?.statusChangedAt, 2000);
  assert.equal(room?.statusChangedBy, "staff-2");
});

test("order context auto-forward upserts one deterministic bubble and preserves createdAt", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  const base = {
    chatId: "cust_u8",
    customerId: "u8",
    orderId: "order8",
    schemaVersion: 1,
    order: {
      orderNumber: "ORD-8",
      status: "PENDING",
      paymentStatus: "PENDING",
      paymentProofStatus: "PENDING_REVIEW",
      total: 80000,
      itemCount: 2,
      hasPaymentProof: true,
      proofVersion: 1,
      createdAt: "2026-07-15T00:00:00.000Z",
    },
  };
  const first = await upsertOrderContextMessage({ firestore, now: () => 1000 }, base);
  const second = await upsertOrderContextMessage(
    { firestore, now: () => 2000 },
    { ...base, order: { ...base.order, proofVersion: 2 } },
  );

  assert.equal(first.messageId, "order_context_order8");
  assert.equal(second.messageId, first.messageId);
  assert.equal(first.created, true);
  assert.equal(second.created, false);
  const messages = [...store.entries()].filter(([key]) => key.startsWith("customerChats/cust_u8/messages/"));
  assert.equal(messages.length, 1);
  assert.equal(messages[0][1].createdAt, 1000);
  assert.equal(messages[0][1].updatedAt, 2000);
  assert.equal((messages[0][1].order as Record<string, unknown>).proofVersion, 2);

  const stale = await upsertOrderContextMessage(
    { firestore, now: () => 3000 },
    base,
  );
  assert.equal(stale.applied, false);
  assert.equal((messages[0][1].order as Record<string, unknown>).proofVersion, 2);
  assert.equal(messages[0][1].updatedAt, 2000);
});

test("refreshOnly updates existing order card without bumping the room", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  const base = {
    chatId: "cust_u9", customerId: "u9", orderId: "order9", schemaVersion: 1,
    order: { orderNumber: "ORD-9", status: "PENDING", paymentStatus: "UNPAID",
      paymentProofStatus: "PENDING_REVIEW", total: 1000, itemCount: 2,
      hasPaymentProof: true, proofVersion: 1, createdAt: "2026-10-07T00:00:00.000Z" },
  };
  await upsertOrderContextMessage({ firestore, now: () => 1000 }, base);
  const roomBefore = { ...store.get("customerChats/cust_u9")! };
  const res = await upsertOrderContextMessage({ firestore, now: () => 5000 }, {
    ...base, refreshOnly: true,
    order: { ...base.order, paymentStatus: "PAID", paymentProofStatus: "VERIFIED",
      reviewedAt: "2026-10-07T03:31:00.000Z", reviewedByName: "Natasha" },
  });
  assert.equal(res.applied, true);
  assert.deepEqual(store.get("customerChats/cust_u9"), roomBefore);
  const msg = store.get("customerChats/cust_u9/messages/order_context_order9")!;
  assert.equal((msg.order as Record<string, unknown>).paymentProofStatus, "VERIFIED");
  assert.equal((msg.order as Record<string, unknown>).reviewedByName, "Natasha");
  assert.equal(msg.createdAt, 1000);
});

test("refreshOnly creates the card and bumps room when card is missing", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  const res = await upsertOrderContextMessage({ firestore, now: () => 7000 }, {
    chatId: "cust_u10", customerId: "u10", orderId: "order10", schemaVersion: 1,
    refreshOnly: true,
    order: { orderNumber: "ORD-10", status: "PAID", paymentStatus: "PAID",
      paymentProofStatus: "VERIFIED", total: 1, itemCount: 1,
      hasPaymentProof: true, proofVersion: 1, createdAt: "2026-10-07T00:00:00.000Z" },
  });
  assert.equal(res.created, true);
  assert.equal(store.get("customerChats/cust_u10")!.lastMessageAt, 7000);
});

test("writeOrderReviewNotice writes one staff-only system message per proof version", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  const input = { chatId: "cust_u9", orderId: "order9", proofVersion: 1, outcome: "VERIFIED" as const,
    text: "Natasha menandai pembayaran ORD-9 sudah masuk" };
  const a = await writeOrderReviewNotice({ firestore, now: () => 6000 }, input);
  const b = await writeOrderReviewNotice({ firestore, now: () => 6500 }, input);
  assert.equal(a.messageId, "order_review_order9_v1_verified");
  assert.equal(a.created, true);
  assert.equal(b.created, false);
  const msg = store.get("customerChats/cust_u9/messages/order_review_order9_v1_verified")!;
  assert.equal(msg.staffOnly, true);
  assert.equal(msg.senderRole, "system");
  assert.equal(msg.type, "system");
  assert.equal(msg.createdAt, 6000);
  assert.equal(store.has("customerChats/cust_u9"), false); // room tidak disentuh
});

test("upsert replaces order wholesale: no stale review fields, other message fields survive", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  const base = {
    chatId: "cust_u11", customerId: "u11", orderId: "order11", schemaVersion: 1,
    order: { orderNumber: "ORD-11", status: "PENDING", paymentStatus: "UNPAID",
      paymentProofStatus: "REJECTED", total: 1000, itemCount: 2,
      hasPaymentProof: true, proofVersion: 1, createdAt: "2026-10-07T00:00:00.000Z",
      rejectReason: "x", reviewedByName: "Natasha", reviewedAt: "2026-10-07T03:31:00.000Z" },
  };
  await upsertOrderContextMessage({ firestore, now: () => 1000 }, base);
  const path = "customerChats/cust_u11/messages/order_context_order11";
  store.set(path, { ...store.get(path)!, readByStaffAt: 123 });
  const { rejectReason, reviewedByName, reviewedAt, ...fresh } = base.order;
  void rejectReason; void reviewedByName; void reviewedAt;
  await upsertOrderContextMessage({ firestore, now: () => 2000 }, {
    ...base, order: { ...fresh, paymentProofStatus: "PENDING_REVIEW", proofVersion: 2 },
  });
  const msg = store.get(path)!;
  const order = msg.order as Record<string, unknown>;
  assert.equal(order.proofVersion, 2);
  assert.equal("rejectReason" in order, false);
  assert.equal("reviewedByName" in order, false);
  assert.equal("reviewedAt" in order, false);
  assert.equal(msg.readByStaffAt, 123);
  assert.equal(msg.createdAt, 1000);
});

// ---------------------------------------------------------------------------
// Pengiriman kartu + catatan staf (deliverOrderContextPayload) — urutan nyata
// tolak / tandai lunas / cek bukti pada versi bukti yang sama.
// ---------------------------------------------------------------------------
function dbOrder(over: Partial<OrderRefreshSource> = {}): OrderRefreshSource {
  return {
    id: "orderA", userId: "uA", orderNumber: "ORD-A", status: "PENDING",
    paymentStatus: "UNPAID", paymentProofStatus: "PENDING_REVIEW",
    paymentProofUrl: "https://bukti", paymentProofVersion: 1,
    paymentProofReviewedAt: null, paymentProofRejectReason: null,
    total: 50000, createdAt: new Date("2026-10-07T00:00:00Z"), _count: { items: 2 },
    ...over,
  };
}

function reviewNotes(store: Map<string, Record<string, unknown>>, chatId: string) {
  return [...store.entries()]
    .filter(([k]) => k.startsWith(`customerChats/${chatId}/messages/order_review_`))
    .map(([k, v]) => ({ id: k.split("/").pop()!, text: v.text as string }));
}

test("case A: tolak v1 lalu admin tandai lunas -> dua catatan, kartu tanpa 'Admin toko'", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  const rejectedDb = dbOrder({
    paymentProofStatus: "REJECTED",
    paymentProofReviewedAt: new Date("2026-10-07T03:00:00Z"),
    paymentProofRejectReason: "nominal kurang",
  });
  const reject = buildOrderContextRefreshPayload(rejectedDb, { outcome: "REJECTED", byName: "Natasha" })!;
  const r1 = await deliverOrderContextPayload({ firestore, now: () => 1000 }, reject);
  assert.equal(r1.applied, true);

  const paid = buildOrderContextRefreshPayload(
    { ...rejectedDb, status: "PAID", paymentStatus: "PAID" },
    { outcome: "PAID", byName: "Admin toko" },
  )!;
  const r2 = await deliverOrderContextPayload({ firestore, now: () => 2000 }, paid);
  assert.equal(r2.applied, true);
  assert.equal(r2.noticeWritten, true);

  const notes = reviewNotes(store, "cust_uA");
  assert.deepEqual(notes.map((n) => n.id).sort(), [
    "order_review_orderA_v1_paid",
    "order_review_orderA_v1_rejected",
  ]);
  assert.equal(
    notes.find((n) => n.id.endsWith("_paid"))!.text,
    "Admin toko menandai pesanan ORD-A sudah lunas",
  );
  const card = store.get("customerChats/cust_uA/messages/order_context_orderA")!;
  const order = card.order as Record<string, unknown>;
  assert.equal(order.paymentStatus, "PAID");
  assert.equal(order.paymentProofStatus, "REJECTED");
  assert.equal("reviewedByName" in order, false);
  assert.equal(JSON.stringify(card).includes("Admin toko"), false);
});

test("case B: admin tandai lunas saat v1 menunggu, lalu Natasha cek v1 -> nama Natasha, dua catatan", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  const paidDb = dbOrder({ status: "PAID", paymentStatus: "PAID" });
  const paid = buildOrderContextRefreshPayload(paidDb, { outcome: "PAID", byName: "Admin toko" })!;
  await deliverOrderContextPayload({ firestore, now: () => 1000 }, paid);
  const mid = store.get("customerChats/cust_uA/messages/order_context_orderA")!.order as Record<string, unknown>;
  assert.equal("reviewedByName" in mid, false);

  const verified = buildOrderContextRefreshPayload(
    { ...paidDb, paymentProofStatus: "VERIFIED", paymentProofReviewedAt: new Date("2026-10-07T04:00:00Z") },
    { outcome: "VERIFIED", byName: "Natasha" },
  )!;
  const r = await deliverOrderContextPayload({ firestore, now: () => 2000 }, verified);
  assert.equal(r.applied, true);
  assert.equal(r.noticeWritten, true);

  const order = store.get("customerChats/cust_uA/messages/order_context_orderA")!.order as Record<string, unknown>;
  assert.equal(order.reviewedByName, "Natasha");
  assert.equal(order.paymentProofStatus, "VERIFIED");
  assert.deepEqual(reviewNotes(store, "cust_uA").map((n) => n.id).sort(), [
    "order_review_orderA_v1_paid",
    "order_review_orderA_v1_verified",
  ]);
});

test("muatan basi (versi bukti lebih lama dari kartu) tidak menulis catatan", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  const v2 = buildOrderContextRefreshPayload(
    dbOrder({ paymentProofVersion: 2 }),
    { outcome: "VERIFIED", byName: "Natasha" },
  )!;
  await deliverOrderContextPayload({ firestore, now: () => 1000 }, { ...v2, notice: undefined });
  const stale = buildOrderContextRefreshPayload(
    dbOrder({ paymentProofStatus: "REJECTED", paymentProofRejectReason: "buram" }),
    { outcome: "REJECTED", byName: "Natasha" },
  )!;
  const r = await deliverOrderContextPayload({ firestore, now: () => 2000 }, stale);
  assert.equal(r.applied, false);
  assert.equal(r.noticeWritten, false);
  assert.equal(reviewNotes(store, "cust_uA").length, 0);
  const order = store.get("customerChats/cust_uA/messages/order_context_orderA")!.order as Record<string, unknown>;
  assert.equal(order.proofVersion, 2);
});

test("ulang kirim aksi yang sama tidak menggandakan catatan", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  const p = buildOrderContextRefreshPayload(dbOrder(), { outcome: "PAID", byName: "Admin toko" })!;
  await deliverOrderContextPayload({ firestore, now: () => 1000 }, p);
  const again = await deliverOrderContextPayload({ firestore, now: () => 2000 }, p);
  assert.equal(again.applied, true);
  assert.equal(again.noticeWritten, false);
  assert.equal(reviewNotes(store, "cust_uA").length, 1);
});

// ---------------------------------------------------------------------------
// Nama & ringkasan pembeli ikut ditulis ke room oleh kartu bukti transfer
// (pembeli web yang belum pernah chat dulu tampil "Pelanggan").
// ---------------------------------------------------------------------------

const snapOrder = {
  orderNumber: "ORD-S1", status: "PENDING", paymentStatus: "UNPAID",
  paymentProofStatus: "PENDING_REVIEW", total: 166400, itemCount: 6,
  hasPaymentProof: true, proofVersion: 1, createdAt: "2026-10-22T00:00:00.000Z",
};
const snapshotSusanto = buildCustomerSnapshot(
  { name: "Susanto Hadi", phone: "0812" },
  { totalBelanja: 500000, orderCount: 3, lastOrder: { inv: "ORD-S0", status: "COMPLETED", total: 100 } },
  () => 900,
);

test("kartu pertama menulis nama, nomor HP, dan ringkasan belanja ke room", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  await upsertOrderContextMessage({ firestore, now: () => 1000 }, {
    chatId: "cust_s1", customerId: "s1", orderId: "os1", schemaVersion: 1,
    order: snapOrder, snapshot: snapshotSusanto,
  });
  const room = store.get("customerChats/cust_s1")!;
  assert.equal(room.customerName, "Susanto Hadi");
  assert.equal(room.customerPhone, "0812");
  assert.deepEqual(room.summary, snapshotSusanto.summary);
  assert.equal(room.summaryUpdatedAt, 900);
  assert.equal(room.lastMessageAt, 1000);
});

test("refreshOnly mengisi nama yang kosong tanpa menaikkan urutan chat", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  await upsertOrderContextMessage({ firestore, now: () => 1000 }, {
    chatId: "cust_s2", customerId: "s2", orderId: "os2", schemaVersion: 1, order: snapOrder,
  });
  assert.equal(store.get("customerChats/cust_s2")!.customerName, undefined);
  await upsertOrderContextMessage({ firestore, now: () => 5000 }, {
    chatId: "cust_s2", customerId: "s2", orderId: "os2", schemaVersion: 1, refreshOnly: true,
    order: { ...snapOrder, paymentStatus: "PAID", paymentProofStatus: "VERIFIED" },
    snapshot: snapshotSusanto,
  });
  const room = store.get("customerChats/cust_s2")!;
  assert.equal(room.customerName, "Susanto Hadi");
  assert.deepEqual(room.summary, snapshotSusanto.summary);
  assert.equal(room.lastMessageAt, 1000);
  assert.equal(room.updatedAt, 1000);
});

test("nama/nomor kosong di snapshot tidak menimpa nama yang sudah ada", async () => {
  const store = new Map<string, Record<string, unknown>>();
  store.set("customerChats/cust_s3", { customerId: "s3", customerName: "Maddy", customerPhone: "0813", lastMessageAt: 10 });
  const firestore = makeFakeFirestore(store);
  await upsertOrderContextMessage({ firestore, now: () => 1000 }, {
    chatId: "cust_s3", customerId: "s3", orderId: "os3", schemaVersion: 1, order: snapOrder,
    snapshot: buildCustomerSnapshot({ name: "  ", phone: null }, { totalBelanja: 0, orderCount: 0 }, () => 1),
  });
  const room = store.get("customerChats/cust_s3")!;
  assert.equal(room.customerName, "Maddy");
  assert.equal(room.customerPhone, "0813");
});

test("muatan basi tidak menulis apa pun ke room, termasuk nama", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  await upsertOrderContextMessage({ firestore, now: () => 1000 }, {
    chatId: "cust_s4", customerId: "s4", orderId: "os4", schemaVersion: 1,
    order: { ...snapOrder, proofVersion: 2 },
  });
  const before = { ...store.get("customerChats/cust_s4")! };
  const res = await upsertOrderContextMessage({ firestore, now: () => 2000 }, {
    chatId: "cust_s4", customerId: "s4", orderId: "os4", schemaVersion: 1, order: snapOrder,
    snapshot: snapshotSusanto,
  });
  assert.equal(res.applied, false);
  assert.deepEqual(store.get("customerChats/cust_s4"), before);
});

test("pesan chat dengan nama akun kosong tidak menghapus nama yang sudah ada", async () => {
  const store = new Map<string, Record<string, unknown>>();
  store.set("customerChats/cust_s5", { customerId: "s5", customerName: "Budi Santoso", customerPhone: "0814" });
  const firestore = makeFakeFirestore(store);
  await writeCustomerMessage({ firestore, now: () => 3000 }, {
    ...buildCustomerSnapshot({ name: "", phone: "" }, { totalBelanja: 0, orderCount: 0 }, () => 1),
    chatId: "cust_s5", customerId: "s5", senderRole: "customer", senderId: "s5",
    type: "text", text: "halo", clientMsgId: "c-s5-1",
  });
  const room = store.get("customerChats/cust_s5")!;
  assert.equal(room.customerName, "Budi Santoso");
  assert.equal(room.customerPhone, "0814");
  assert.equal(room.lastMessageText, "halo");
});

test("deliverOrderContextPayload meneruskan data pembeli ke room", async () => {
  const store = new Map<string, Record<string, unknown>>();
  const firestore = makeFakeFirestore(store);
  await deliverOrderContextPayload({ firestore, now: () => 1000 }, {
    schemaVersion: 1, order: snapOrder, orderId: "os6", customerId: "s6",
  }, snapshotSusanto);
  assert.equal(store.get("customerChats/cust_s6")!.customerName, "Susanto Hadi");
});

test("refreshOnly tidak membuat room kosong bila room belum ada", async () => {
  const store = new Map<string, Record<string, unknown>>();
  store.set("customerChats/cust_s7/messages/order_context_os7", {
    type: "order_context", createdAt: 1, order: { ...snapOrder },
  });
  const firestore = makeFakeFirestore(store);
  await upsertOrderContextMessage({ firestore, now: () => 2000 }, {
    chatId: "cust_s7", customerId: "s7", orderId: "os7", schemaVersion: 1, refreshOnly: true,
    order: snapOrder, snapshot: snapshotSusanto,
  });
  assert.equal(store.has("customerChats/cust_s7"), false);
});
