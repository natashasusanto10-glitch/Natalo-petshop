const DEFAULT_ENDPOINT = "https://api.fonnte.com/send";
const DEFAULT_SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
const DEFAULT_BRAND = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";
const MIN_SEND_INTERVAL_MS = Number(process.env.WA_MIN_SEND_INTERVAL_MS || 1200);
const DEDUPE_WINDOW_MS = Number(process.env.WA_DEDUPE_WINDOW_MS || 2 * 60 * 1000);
const MAX_RETRIES = Number(process.env.WA_MAX_RETRIES || 3);
const RETRY_DELAY_MS = Number(process.env.WA_RETRY_DELAY_MS || 5 * 60 * 1000);

const sentRecently = new Map();
let sendQueue = Promise.resolve();
let lastSentAt = 0;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function formatRupiah(value) {
  return new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: "IDR",
    maximumFractionDigits: 0,
  }).format(Number(value || 0));
}

export function formatWaPhone(value) {
  const digits = String(value || "").replace(/\D/g, "");

  if (!digits) return "";
  if (digits.startsWith("62")) return digits;
  if (digits.startsWith("0")) return `62${digits.slice(1)}`;
  if (digits.startsWith("8")) return `62${digits}`;

  return digits;
}

function cleanRecentDedupe(now) {
  for (const [key, timestamp] of sentRecently.entries()) {
    if (now - timestamp > DEDUPE_WINDOW_MS) sentRecently.delete(key);
  }
}

function shouldSkipDuplicate(phone, message) {
  const now = Date.now();
  cleanRecentDedupe(now);

  const key = `${phone}:${message}`;
  const previous = sentRecently.get(key);
  if (previous && now - previous < DEDUPE_WINDOW_MS) return true;

  sentRecently.set(key, now);
  return false;
}

function fillTemplate(template, values) {
  return template.replace(/\{(\w+)\}/g, (_, key) => {
    const value = values[key];
    return value === undefined || value === null ? "" : String(value);
  });
}

function firstValue(...values) {
  return values.find((value) => value !== undefined && value !== null && value !== "");
}

function getOrderNotifyPhone() {
  return firstValue(
    process.env.WA_ORDER_NOTIFY_PHONE,
    process.env.NEXT_PUBLIC_WA_NUMBER,
    process.env.NEXT_PUBLIC_WHATSAPP_NUMBER,
    process.env.FONNTE_DEVICE
  );
}

function getOrderValues(order = {}) {
  const orderNumber = firstValue(order.orderNumber, order.order_number, order.order_id, order.id, "");
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || DEFAULT_SITE_URL;
  const trackingToken = firstValue(order.trackingToken, order.tracking_token, "");
  const orderUrl = trackingToken
    ? `${siteUrl}/pesanan/${encodeURIComponent(orderNumber)}?token=${encodeURIComponent(trackingToken)}`
    : `${siteUrl}/pesanan/${encodeURIComponent(orderNumber)}`;
  const paymentUrl = firstValue(order.paymentUrl, order.payment_url, orderUrl);
  const trackingUrl = firstValue(order.trackingUrl, order.tracking_url, orderUrl);
  const reviewUrl = firstValue(order.reviewUrl, order.review_url, `${siteUrl}/member/reviews`);

  return {
    brand: process.env.NEXT_PUBLIC_BRAND_NAME || DEFAULT_BRAND,
    customerName: firstValue(order.customerName, order.customer_name, "Kak"),
    orderNumber,
    total: formatRupiah(firstValue(order.total, order.grandTotal, order.total_amount, 0)),
    orderUrl,
    paymentUrl,
    courier: firstValue(order.courierService, order.courierCode, order.courier, "-"),
    trackingNumber: firstValue(order.trackingNumber, order.tracking_number, "-"),
    trackingUrl,
    eta: firstValue(order.eta, "1-3"),
    cancelReason: firstValue(order.cancelReason, order.cancel_reason, "Tidak ada catatan tambahan."),
    refundAmount: formatRupiah(firstValue(order.refundAmount, order.refund_amount, 0)),
    reviewUrl,
  };
}

function getOrderItemsText(order = {}) {
  const items = Array.isArray(order.items) ? order.items : [];
  if (items.length === 0) return "-";

  return items
    .map((item) => {
      const variant = item.variantLabel || item.variant_label ? ` (${item.variantLabel || item.variant_label})` : "";
      const quantity = item.quantity || 0;
      const price = formatRupiah(item.price || 0);
      return `- ${item.name}${variant} x${quantity} @ ${price}`;
    })
    .join("\n");
}

const templates = {
  orderCreated:
    process.env.WA_TEMPLATE_ORDER_CREATED ||
    [
      "Halo {customerName}!",
      "",
      "Pesanan kamu di *{brand}* sudah kami terima.",
      "",
      "*Detail Pesanan:*",
      "No. Order: {orderNumber}",
      "Total: {total}",
      "",
      "Selesaikan pembayaran dalam *24 jam* agar pesanan tidak dibatalkan.",
      "Bayar di sini: {paymentUrl}",
      "",
      "Terima kasih sudah belanja di {brand}.",
    ].join("\n"),
  paymentConfirmed:
    process.env.WA_TEMPLATE_PAYMENT_CONFIRMED ||
    [
      "*Pembayaran Diterima!*",
      "",
      "Halo {customerName}, pembayaran untuk pesanan *{orderNumber}* sebesar {total} sudah kami terima.",
      "",
      "Pesanan kamu sedang kami proses dan akan segera dikirim.",
      "",
      "Kami akan kabari lagi saat paket sudah di tangan kurir ya.",
      "Terima kasih sudah berbelanja di {brand}.",
    ].join("\n"),
  orderShipped:
    process.env.WA_TEMPLATE_ORDER_SHIPPED ||
    [
      "*Pesanan Sedang Dikirim!*",
      "",
      "Halo {customerName}, paket pesanan *{orderNumber}* sudah kami serahkan ke kurir.",
      "",
      "*Info Pengiriman:*",
      "Kurir: {courier}",
      "Resi: *{trackingNumber}*",
      "",
      "Lacak pesanan: {trackingUrl}",
      "",
      "Semoga cepat sampai. Kalau ada pertanyaan, balas pesan ini ya.",
    ].join("\n"),
  orderCompleted:
    process.env.WA_TEMPLATE_ORDER_COMPLETED ||
    [
      "*Pesanan Selesai!*",
      "",
      "Halo {customerName}, pesanan *{orderNumber}* sudah selesai.",
      "",
      "Kasih ulasan di sini: {reviewUrl}",
      "Ulasan kamu sangat berarti untuk kami.",
      "",
      "Sampai belanja lagi di {brand}.",
    ].join("\n"),
  orderCancelled:
    process.env.WA_TEMPLATE_ORDER_CANCELLED ||
    [
      "*Pesanan Dibatalkan*",
      "",
      "Halo {customerName}, pesanan *{orderNumber}* telah dibatalkan.",
      "",
      "Alasan: {cancelReason}",
      "Refund: {refundAmount}",
      "",
      "Kalau ada pertanyaan, hubungi kami via WhatsApp atau balas pesan ini.",
      "{brand}",
    ].join("\n"),
  adminOrderCreated:
    process.env.WA_TEMPLATE_ADMIN_ORDER_CREATED ||
    [
      "*Order Baru Masuk*",
      "",
      "No. Order: {orderNumber}",
      "Customer: {customerName}",
      "WhatsApp: {customerPhone}",
      "Total: {total}",
      "Pembayaran: {paymentProvider}",
      "Pengiriman: {shippingMethod}",
      "",
      "*Produk:*",
      "{itemsText}",
      "",
      "Detail admin: {adminOrderUrl}",
    ].join("\n"),
};

async function callFonnte(phone, message) {
  const token = process.env.FONNTE_TOKEN?.trim();
  if (!token) {
    return {
      ok: false,
      skipped: true,
      reason: "FONNTE_TOKEN belum diisi.",
    };
  }

  const body = new URLSearchParams();
  body.set("target", phone);
  body.set("message", message);
  body.set("countryCode", "62");

  const response = await fetch(process.env.FONNTE_ENDPOINT || DEFAULT_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: token,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });

  const text = await response.text();
  let payload = text;
  try {
    payload = JSON.parse(text);
  } catch {
    // Fonnte can return plain text on some failures.
  }

  const apiFailed = typeof payload === "object" && payload !== null && payload.status === false;
  if (!response.ok || apiFailed) {
    throw new Error(
      `Fonnte HTTP ${response.status}: ${
        typeof payload === "string" ? payload : JSON.stringify(payload)
      }`
    );
  }

  return { ok: true, phone, message, response: payload };
}

async function sendWithRetry(phone, message, attempt = 1) {
  try {
    return await callFonnte(phone, message);
  } catch (error) {
    console.error("[whatsapp] send failed", {
      phone,
      attempt,
      error: error instanceof Error ? error.message : error,
    });

    if (attempt >= MAX_RETRIES) {
      return {
        ok: false,
        phone,
        message,
        error: error instanceof Error ? error.message : String(error),
      };
    }

    setTimeout(() => {
      enqueueSend(phone, message, attempt + 1).catch((retryError) => {
        console.error("[whatsapp] retry queue failed", retryError);
      });
    }, RETRY_DELAY_MS);

    return {
      ok: false,
      retryScheduled: true,
      phone,
      message,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

function enqueueSend(phone, message, attempt = 1) {
  sendQueue = sendQueue.then(async () => {
    const elapsed = Date.now() - lastSentAt;
    if (elapsed < MIN_SEND_INTERVAL_MS) {
      await sleep(MIN_SEND_INTERVAL_MS - elapsed);
    }

    const result = await sendWithRetry(phone, message, attempt);
    lastSentAt = Date.now();
    return result;
  });

  return sendQueue;
}

export async function sendWA(phoneValue, message) {
  const phone = formatWaPhone(phoneValue);
  const text = String(message || "").trim();

  if (!phone || !text) {
    return { ok: false, skipped: true, reason: "Nomor atau pesan kosong." };
  }

  if (shouldSkipDuplicate(phone, text)) {
    return { ok: true, skipped: true, reason: "Duplicate message skipped." };
  }

  return enqueueSend(phone, text);
}

export function sendWAFireAndForget(phone, message) {
  sendWA(phone, message).catch((error) => {
    console.error("[whatsapp] fire-and-forget failed", error);
  });
}

export function buildOrderMessage(type, order) {
  const template = templates[type];
  if (!template) throw new Error(`Template WA tidak ditemukan: ${type}`);
  return fillTemplate(template, getOrderValues(order));
}

export function sendCustomMessage(phone, message) {
  return sendWA(phone, message);
}

export function sendOrderCreated(order) {
  return sendWA(
    firstValue(order.customerPhone, order.customer_phone),
    buildOrderMessage("orderCreated", order)
  );
}

export function buildAdminOrderCreatedMessage(order) {
  const values = getOrderValues(order);
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || DEFAULT_SITE_URL;
  const courier = firstValue(order.courierService, order.courier_service, order.courierCode, order.courier_code, "-");
  return fillTemplate(templates.adminOrderCreated, {
    ...values,
    customerPhone: firstValue(order.customerPhone, order.customer_phone, "-"),
    paymentProvider: firstValue(order.paymentProvider, order.payment_provider, "-"),
    shippingMethod: courier,
    itemsText: getOrderItemsText(order),
    adminOrderUrl: `${siteUrl}/admin/orders/${order.id || ""}`,
  });
}

export function sendAdminOrderCreated(order) {
  return sendWA(getOrderNotifyPhone(), buildAdminOrderCreatedMessage(order));
}

export function sendPaymentConfirmed(order) {
  return sendWA(
    firstValue(order.customerPhone, order.customer_phone),
    buildOrderMessage("paymentConfirmed", order)
  );
}

export function sendOrderShipped(order) {
  return sendWA(
    firstValue(order.customerPhone, order.customer_phone),
    buildOrderMessage("orderShipped", order)
  );
}

export function sendOrderCompleted(order) {
  return sendWA(
    firstValue(order.customerPhone, order.customer_phone),
    buildOrderMessage("orderCompleted", order)
  );
}

export function sendOrderCancelled(order) {
  return sendWA(
    firstValue(order.customerPhone, order.customer_phone),
    buildOrderMessage("orderCancelled", order)
  );
}

export const WhatsAppService = {
  formatWaPhone,
  sendWA,
  sendWAFireAndForget,
  buildOrderMessage,
  buildAdminOrderCreatedMessage,
  sendCustomMessage,
  sendOrderCreated,
  sendAdminOrderCreated,
  sendPaymentConfirmed,
  sendOrderShipped,
  sendOrderCompleted,
  sendOrderCancelled,
};
