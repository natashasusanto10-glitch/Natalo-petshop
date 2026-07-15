import { createHmac, timingSafeEqual } from "node:crypto";
import type { OrderContextV1 } from "@/lib/chat/order-contract";

export function chatIdForUser(userId: string): string {
  return `cust_${userId}`;
}

// Tipe pesan yang aman untuk customer. Field internal SENGAJA tak ikut.
export type CustomerMessage = {
  id?: string;
  clientMsgId?: string;
  senderRole: "customer" | "staff";
  senderName?: string;
  type: "text" | "image" | "product" | "product_context" | "order_context" | "system";
  text?: string;
  image?: { url: string };
  product?: { productId: string; slug?: string; name: string; imageUrl?: string; price?: number; stock?: number };
  order?: Partial<OrderContextV1["order"]> & { orderNumber: string };
  schemaVersion?: number;
  // Kutipan balasan — hanya field aman (id/senderName/type/text preview).
  // TAK ADA data internal; text sudah di-preview server saat penulisan.
  replyTo?: { id?: string; senderName?: string; type?: string; text?: string };
  auto?: boolean;
  createdAt: number;
  status?: string;
  readByCustomerAt?: number;
};

const ALLOWED_TYPES = new Set([
  "text", "image", "product", "product_context", "order_context", "system",
]);

export function projectMessageForCustomer(raw: unknown): CustomerMessage | null {
  if (!raw || typeof raw !== "object") return null;
  const m = raw as Record<string, unknown>;
  if (m.staffOnly === true) return null;
  const type = m.type;
  if (typeof type !== "string" || !ALLOWED_TYPES.has(type)) return null;

  const out: CustomerMessage = {
    senderRole: m.senderRole === "staff" ? "staff" : "customer",
    type: type as CustomerMessage["type"],
    createdAt: typeof m.createdAt === "number" ? m.createdAt : 0,
  };
  if (typeof m.id === "string") out.id = m.id;
  if (typeof m.clientMsgId === "string") out.clientMsgId = m.clientMsgId;
  if (typeof m.senderName === "string") out.senderName = m.senderName;
  if (typeof m.text === "string") out.text = m.text;
  if (m.image && typeof (m.image as Record<string, unknown>).url === "string") {
    out.image = { url: (m.image as { url: string }).url };
  }
  if (m.product && typeof m.product === "object") {
    const p = m.product as Record<string, unknown>;
    // Allowlist eksplisit per-field: JANGAN cast seluruh objek (bisa bocorkan cost/margin/supplier dll).
    const product: Partial<NonNullable<CustomerMessage["product"]>> = {};
    if (typeof p.productId === "string") product.productId = p.productId;
    if (typeof p.slug === "string") product.slug = p.slug;
    if (typeof p.name === "string") product.name = p.name;
    if (typeof p.imageUrl === "string") product.imageUrl = p.imageUrl;
    if (typeof p.price === "number") product.price = p.price;
    if (typeof p.stock === "number") product.stock = p.stock;
    out.product = product as CustomerMessage["product"];
  }
  if (m.order && typeof m.order === "object") {
    const o = m.order as Record<string, unknown>;
    // Allowlist eksplisit per-field: JANGAN cast seluruh objek (bisa bocorkan cost/margin internal dll).
    const order: Partial<NonNullable<CustomerMessage["order"]>> = {};
    if (typeof o.orderNumber === "string") order.orderNumber = o.orderNumber;
    if (typeof o.status === "string") order.status = o.status;
    if (typeof o.paymentStatus === "string") order.paymentStatus = o.paymentStatus;
    if (typeof o.paymentProofStatus === "string") order.paymentProofStatus = o.paymentProofStatus;
    if (typeof o.total === "number") order.total = o.total;
    if (typeof o.itemCount === "number") order.itemCount = o.itemCount;
    if (typeof o.hasPaymentProof === "boolean") order.hasPaymentProof = o.hasPaymentProof;
    if (typeof o.proofVersion === "number") order.proofVersion = o.proofVersion;
    if (typeof o.createdAt === "string") order.createdAt = o.createdAt;
    out.order = order as CustomerMessage["order"];
  }
  if (typeof m.schemaVersion === "number") out.schemaVersion = m.schemaVersion;
  if (m.replyTo && typeof m.replyTo === "object") {
    const r = m.replyTo as Record<string, unknown>;
    // Allowlist per-field — sama disiplin dgn product/order (jangan cast objek utuh).
    const replyTo: NonNullable<CustomerMessage["replyTo"]> = {};
    if (typeof r.id === "string") replyTo.id = r.id;
    if (typeof r.senderName === "string") replyTo.senderName = r.senderName;
    if (typeof r.type === "string") replyTo.type = r.type;
    if (typeof r.text === "string") replyTo.text = r.text;
    out.replyTo = replyTo;
  }
  if (m.auto === true) out.auto = true;
  if (typeof m.status === "string") out.status = m.status;
  if (typeof m.readByCustomerAt === "number") out.readByCustomerAt = m.readByCustomerAt;
  return out;
}

export function isValidClientMsgId(v: unknown): v is string {
  return typeof v === "string" && v.length >= 8 && v.length <= 64 && /^[A-Za-z0-9_-]+$/.test(v);
}

export function verifyWebhookSignature(rawBody: string, header: string, secret: string): boolean {
  if (!header || !secret) return false;
  const expected = createHmac("sha256", secret).update(rawBody).digest("hex");
  const a = Buffer.from(expected, "hex");
  let b: Buffer;
  try { b = Buffer.from(header, "hex"); } catch { return false; }
  if (a.length !== b.length || a.length === 0) return false;
  return timingSafeEqual(a, b);
}

export function slidingWindowAllow(
  timestampsMs: number[], nowMs: number, limit: number, windowMs: number,
): boolean {
  const cutoff = nowMs - windowMs;
  const recent = timestampsMs.filter((t) => t > cutoff);
  return recent.length < limit;
}

export function parseChatEnabled(doc: unknown): boolean {
  if (!doc || typeof doc !== "object") return true;
  return (doc as Record<string, unknown>).chatEnabled !== false;
}

// Status jam operasional (WIB, UTC+7 tanpa DST) dari doc app_settings/chatHours.
// Dipakai: (a) GET /api/chat/config → status "Online / Di luar jam" (fix B3);
// (b) POST /api/chat/send → pilih auto-greeting vs auto-away (Task 5).
const WIB_OFFSET_MS = 7 * 60 * 60 * 1000;
const DOW = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
export function computeChatHoursStatus(
  hoursDoc: unknown, nowUtcMs: number,
): { online: boolean; timezone: string; todayOpen: string | null; todayClose: string | null } {
  const doc = (hoursDoc && typeof hoursDoc === "object" ? hoursDoc : {}) as Record<string, any>;
  const timezone = typeof doc.timezone === "string" ? doc.timezone : "Asia/Jakarta";
  const wib = new Date(nowUtcMs + WIB_OFFSET_MS);
  const today = (doc.days && doc.days[DOW[wib.getUTCDay()]]) || {};
  const open = typeof today.open === "string" ? today.open : null;
  const close = typeof today.close === "string" ? today.close : null;
  if (!open || !close) return { online: false, timezone, todayOpen: open, todayClose: close };
  const nowHhmm = `${String(wib.getUTCHours()).padStart(2, "0")}:${String(wib.getUTCMinutes()).padStart(2, "0")}`;
  return { online: nowHhmm >= open && nowHhmm < close, timezone, todayOpen: open, todayClose: close };
}
