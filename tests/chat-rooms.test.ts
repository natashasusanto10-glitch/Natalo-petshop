import assert from "node:assert/strict";
import test from "node:test";
import {
  buildCustomerSnapshot,
  writeCustomerMessage,
  type FirestoreLike,
  type CollectionRefLike,
  type DocRefLike,
  type QueryLike,
  type QuerySnapshotLike,
  type DocSnapshotLike,
  type TransactionLike,
} from "@/lib/chat/rooms";

// ---------------------------------------------------------------------------
// Fake Firestore Admin SDK minimal — in-memory, keyed by full doc path
// (mis. "customerChats/cust_u1" atau "customerChats/cust_u1/messages/auto1").
// Mengimplementasikan subset yang dipakai writeCustomerMessage:
//   collection(name).doc(id?) / .where(field, op, value).limit(n).get()
//   runTransaction(fn) -> tx.get(docRef) / tx.set(docRef, data, {merge})
// ---------------------------------------------------------------------------
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
            store.set(ref.path, { ...existing, ...data });
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
