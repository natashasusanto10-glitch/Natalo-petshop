import type { CustomerMessage } from "@/lib/chat/core";

export type WebChatMessage = CustomerMessage & {
  localState?: "sending" | "failed";
  localKey: string;
  /** URL objek lokal untuk pratinjau foto yang sedang dikirim. */
  imagePreviewUrl?: string;
};

const ID_SAFE = /^[A-Za-z0-9_-]{1,80}$/;

function defaultRandom(): string {
  const c = globalThis.crypto;
  if (c?.randomUUID) return c.randomUUID().replace(/-/g, "");
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}

export function newClientMsgId(random: () => string = defaultRandom): string {
  return `web_${random().replace(/[^A-Za-z0-9_-]/g, "").slice(0, 40)}`;
}

export function toWebMessage(m: CustomerMessage): WebChatMessage {
  return { ...m, localKey: m.id ?? m.clientMsgId ?? `t${m.createdAt}` };
}

export function pendingMessage(input: {
  clientMsgId: string; text?: string; imagePreviewUrl?: string; now: number;
}): WebChatMessage {
  return {
    clientMsgId: input.clientMsgId,
    senderRole: "customer",
    type: input.imagePreviewUrl ? "image" : "text",
    text: input.text,
    imagePreviewUrl: input.imagePreviewUrl,
    createdAt: input.now,
    localState: "sending",
    localKey: input.clientMsgId,
  };
}

export function mergeMessages(current: WebChatMessage[], incoming: CustomerMessage[]): WebChatMessage[] {
  const byKey = new Map<string, WebChatMessage>();
  const clientIndex = new Map<string, string>();
  for (const m of current) {
    byKey.set(m.localKey, m);
    if (m.clientMsgId) clientIndex.set(m.clientMsgId, m.localKey);
  }
  for (const raw of incoming) {
    const m = toWebMessage(raw);
    const localKey = m.clientMsgId ? clientIndex.get(m.clientMsgId) : undefined;
    if (localKey && localKey !== m.localKey) byKey.delete(localKey);
    byKey.set(m.localKey, m);
    if (m.clientMsgId) clientIndex.set(m.clientMsgId, m.localKey);
  }
  return [...byKey.values()].sort((a, b) => a.createdAt - b.createdAt);
}

export function markFailed(list: WebChatMessage[], clientMsgId: string): WebChatMessage[] {
  return list.map((m) =>
    m.localState && m.clientMsgId === clientMsgId ? { ...m, localState: "failed" } : m,
  );
}

export function forwardCursor(
  list: WebChatMessage[], serverNextCursor: number | null, prev: number | null,
): number | null {
  if (serverNextCursor !== null) return serverNextCursor;
  let max: number | null = null;
  for (const m of list) {
    if (m.localState) continue;
    if (max === null || m.createdAt > max) max = m.createdAt;
  }
  return max ?? prev;
}

export function orderCardLabel(order: NonNullable<CustomerMessage["order"]>): {
  text: string; tone: "ok" | "warn" | "bad" | "info";
} {
  const pay = (order.paymentStatus ?? "").toUpperCase();
  const proof = (order.paymentProofStatus ?? "").toUpperCase();
  if (pay === "PAID" || proof === "VERIFIED") return { text: "Pembayaran terverifikasi", tone: "ok" };
  if (proof === "REJECTED") return { text: "Bukti transfer ditolak", tone: "bad" };
  if (proof === "PENDING_REVIEW") return { text: "Bukti sedang dicek", tone: "warn" };
  if (pay === "UNPAID" || pay === "PENDING") return { text: "Menunggu pembayaran", tone: "info" };
  return { text: "Pesanan", tone: "info" };
}

export function chatHref(ctx?: { orderNumber?: string; productId?: string }): string {
  if (ctx?.orderNumber) return `/chat?order=${encodeURIComponent(ctx.orderNumber)}`;
  if (ctx?.productId) return `/chat?product=${encodeURIComponent(ctx.productId)}`;
  return "/chat";
}

export type ChatContext =
  | { type: "order"; orderNumber: string }
  | { type: "product"; productId: string };

export function parseChatContext(search: URLSearchParams): ChatContext | null {
  const order = search.get("order");
  if (order && ID_SAFE.test(order)) return { type: "order", orderNumber: order };
  const product = search.get("product");
  if (product && ID_SAFE.test(product)) return { type: "product", productId: product };
  return null;
}
