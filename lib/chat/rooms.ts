/**
 * Penulisan room & pesan `customerChats` (tokochat) — sisi proxy (customer).
 *
 * Desain: `writeCustomerMessage` menerima `deps.firestore` bertipe interface
 * minimal `FirestoreLike` (subset Admin SDK yang benar-benar dipakai), BUKAN
 * tipe `Firestore` dari `firebase-admin/firestore` — supaya lib ini tak
 * mengimpor firebase-admin sama sekali dan bisa di-DI dengan fake murni di
 * test (lihat tests/chat-rooms.test.ts). Di produksi, `getTokochatFirestore()`
 * (lib/chat/firestore-admin.ts) sudah struktural-cocok dengan interface ini
 * (collection/doc/where/get/runTransaction — API Admin SDK asli), jadi bisa
 * dioper langsung tanpa adapter.
 *
 * Kepemilikan tulis (spec §4.2):
 * - `status` / `statusChangedBy` / `statusChangedAt` — HANYA distempel nilai
 *   awal (`waiting_staff`) bila room BENAR-BENAR BARU / field `status` belum
 *   pernah ada (fix F4: tanpa ini, room baru tak pernah match query inbox
 *   staf `where('status', whereIn: [...])` — Firestore whereIn tak match
 *   dokumen yang tak punya field tsb sama sekali, jadi customer baru tak
 *   pernah muncul di inbox). Transisi status SESUDAHNYA (mis. resolved ->
 *   reopen) TETAP bukan tanggung jawab fungsi ini — itu milik auto-reopen
 *   (Task 5, lib/chat/auto-effects.ts) / staff.
 * - `greetingSentAt` (auto-greeting/away = Task 5)
 * - `unreadCount.{staffUid}` / `unreadForCustomer` (increment = Cloud Function
 *   `notifyNewCustomerMessage`, Plan 3 — proxy tak punya akses daftar staff)
 */

// ---------------------------------------------------------------------------
// Interface Firestore minimal (subset Admin SDK) — dipakai sebagai kontrak DI.
// Struktur method sama persis dgn `firebase-admin/firestore` (collection,
// doc, where, get, runTransaction) sehingga `Firestore` asli valid sbg
// `FirestoreLike` tanpa adapter; test cukup buat fake in-memory yang cocok.
// ---------------------------------------------------------------------------

export interface DocSnapshotLike {
  readonly id: string;
  readonly exists: boolean;
  data(): Record<string, unknown> | undefined;
}

export interface QuerySnapshotLike {
  readonly empty: boolean;
  readonly docs: DocSnapshotLike[];
}

export interface QueryLike {
  limit(n: number): QueryLike;
  get(): Promise<QuerySnapshotLike>;
}

export interface DocRefLike {
  readonly id: string;
  readonly path: string;
  collection(name: string): CollectionRefLike;
}

export interface CollectionRefLike {
  doc(id?: string): DocRefLike;
  where(field: string, op: "==", value: unknown): QueryLike;
}

export interface TransactionLike {
  get(ref: DocRefLike): Promise<DocSnapshotLike>;
  set(ref: DocRefLike, data: Record<string, unknown>, options?: { merge?: boolean }): void;
}

export interface FirestoreLike {
  collection(name: string): CollectionRefLike;
  runTransaction<T>(updateFn: (tx: TransactionLike) => Promise<T>): Promise<T>;
}

// ---------------------------------------------------------------------------
// buildCustomerSnapshot — PURE, tanpa query. Data Prisma sudah diambil route
// (Task 5) dan diinject di sini.
// ---------------------------------------------------------------------------

export type CustomerSnapshotUser = {
  name?: string | null;
  phone?: string | null;
};

export type OrderAggregate = {
  totalBelanja: number;
  orderCount: number;
  lastOrder?: { inv: string; status?: string; total?: number } | null;
};

export type CustomerSnapshot = {
  customerName: string;
  customerPhone: string;
  summary: {
    totalBelanja: number;
    orderCount: number;
    lastOrder: { inv: string; status?: string; total?: number } | null;
  };
  summaryUpdatedAt: number;
};

export function buildCustomerSnapshot(
  user: CustomerSnapshotUser,
  orderAgg: OrderAggregate,
  now: () => number = Date.now,
): CustomerSnapshot {
  return {
    customerName: user?.name ?? "",
    customerPhone: user?.phone ?? "",
    summary: {
      totalBelanja: orderAgg.totalBelanja,
      orderCount: orderAgg.orderCount,
      lastOrder: orderAgg.lastOrder ?? null,
    },
    summaryUpdatedAt: now(),
  };
}

// ---------------------------------------------------------------------------
// writeCustomerMessage — idempoten via clientMsgId + merge-update room.
// ---------------------------------------------------------------------------

const ROOM_COLLECTION = "customerChats";
const MESSAGE_SUBCOLLECTION = "messages";

export type ChatMessageType =
  | "text"
  | "image"
  | "product"
  | "product_context"
  | "order_context"
  | "system";

export type WriteCustomerMessageInput = {
  chatId: string;
  customerId: string; // Natalo User.id (cuid) — identitas room (fix B2)
  senderRole: "customer" | "staff";
  senderId: string;
  senderName?: string;
  type: ChatMessageType;
  text?: string;
  image?: { url: string };
  product?: { productId: string; slug?: string; name: string; imageUrl?: string; price?: number; stock?: number };
  order?: { orderNumber: string; status?: string; total?: number };
  // Kutipan balasan — sudah di-derive-ulang server (route) dari pesan asli.
  replyTo?: { id: string; senderName?: string; type?: string; text?: string };
  auto?: boolean;
  staffOnly?: boolean;
  clientMsgId: string;
  // Snapshot customer (opsional — hasil buildCustomerSnapshot, disebar oleh
  // caller: `writeCustomerMessage(deps, { ...snap, chatId, customerId, ... })`).
  customerName?: string;
  customerPhone?: string;
  summary?: CustomerSnapshot["summary"];
  summaryUpdatedAt?: number;
};

export type WriteCustomerMessageDeps = {
  firestore: FirestoreLike;
  now: () => number;
};

export type WriteCustomerMessageResult = {
  messageId: string;
  deduped: boolean;
};

export async function writeCustomerMessage(
  deps: WriteCustomerMessageDeps,
  input: WriteCustomerMessageInput,
): Promise<WriteCustomerMessageResult> {
  const { firestore, now } = deps;
  const roomRef = firestore.collection(ROOM_COLLECTION).doc(input.chatId);
  const messagesRef = roomRef.collection(MESSAGE_SUBCOLLECTION);

  // (a) Dedupe: cek apakah pesan dgn clientMsgId ini sudah pernah ditulis.
  const existing = await messagesRef.where("clientMsgId", "==", input.clientMsgId).limit(1).get();
  if (!existing.empty) {
    return { messageId: existing.docs[0].id, deduped: true };
  }

  const newMessageRef = messagesRef.doc();
  const nowMs = now();

  await firestore.runTransaction(async (tx) => {
    const roomSnap = await tx.get(roomRef);
    const roomData = roomSnap.exists ? roomSnap.data() : undefined;

    // (b) Merge-update room. `customerId` SELALU diset (fix B2 — CF/inbox
    // bergantung pada field ini, jangan hanya derive dari chatId). Unread
    // counters SENGAJA tak disentuh (milik Cloud Function).
    const roomUpdate: Record<string, unknown> = {
      customerId: input.customerId,
      updatedAt: nowMs,
      lastMessageType: input.type,
      lastMessageAt: nowMs,
      lastMessageSender: input.senderRole,
    };
    if (input.text !== undefined) roomUpdate.lastMessageText = input.text;
    if (input.customerName !== undefined) roomUpdate.customerName = input.customerName;
    if (input.customerPhone !== undefined) roomUpdate.customerPhone = input.customerPhone;
    if (input.summary !== undefined) roomUpdate.summary = input.summary;
    if (input.summaryUpdatedAt !== undefined) roomUpdate.summaryUpdatedAt = input.summaryUpdatedAt;
    if (!roomData || roomData.createdAt === undefined) {
      roomUpdate.createdAt = nowMs; // hanya bila absen — cegah double-init
    }
    if (!roomData || roomData.status === undefined) {
      // Fix F4: room baru wajib punya `status` sejak lahir, else whereIn
      // query inbox staf tak pernah menemukannya. `waiting_staff` sama
      // dengan nilai yang dipakai autoReopenIfResolved — customer baru saja
      // menulis, staff yang harus merespons. Guard `undefined`-only berarti
      // status yang SUDAH ada (open/waiting_customer/resolved) tak pernah
      // ditimpa di sini — transisi tetap milik auto-effects/staff.
      roomUpdate.status = "waiting_staff";
      roomUpdate.statusChangedAt = nowMs;
      roomUpdate.statusChangedBy = "system";
    }

    tx.set(roomRef, roomUpdate, { merge: true });

    // (c) Tulis doc pesan baru (dalam transaksi yang sama — atomik dgn room).
    const messageDoc: Record<string, unknown> = {
      clientMsgId: input.clientMsgId,
      senderRole: input.senderRole,
      senderId: input.senderId,
      type: input.type,
      createdAt: nowMs,
      status: "sent",
    };
    if (input.senderName !== undefined) messageDoc.senderName = input.senderName;
    if (input.text !== undefined) messageDoc.text = input.text;
    if (input.image !== undefined) messageDoc.image = input.image;
    if (input.product !== undefined) messageDoc.product = input.product;
    if (input.order !== undefined) messageDoc.order = input.order;
    if (input.replyTo !== undefined) messageDoc.replyTo = input.replyTo;
    if (input.auto !== undefined) messageDoc.auto = input.auto;
    if (input.staffOnly !== undefined) messageDoc.staffOnly = input.staffOnly;

    tx.set(newMessageRef, messageDoc, { merge: false });
  });

  return { messageId: newMessageRef.id, deduped: false };
}
