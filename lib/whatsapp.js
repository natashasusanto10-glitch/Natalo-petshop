// ─────────────────────────────────────────────────────────────────────────────
// WhatsApp gateway — Fonnte
//
// Scope SETELAH cleanup: hanya dipakai untuk kirim OTP register & OTP login.
// Notifikasi order (orderCreated, paymentConfirmed, orderShipped, dst.) sudah
// DIHAPUS — order notifikasi sekarang murni via email + push notification.
//
// Yang tersisa di file ini cuma utility primitives:
// - `formatWaPhone` — normalisasi nomor ke format 62xxx
// - `sendWA` — kirim teks dengan queue + dedupe + retry (anti-spam Fonnte)
// - `sendWAFireAndForget` — convenience untuk caller yg tidak butuh result
// - `sendCustomMessage` — alias semantic ke sendWA (dipakai OTP route)
//
// Apapun yang menambah pesan WA baru di masa depan (mis. OTP login, reminder
// keranjang, dll) cukup pakai `sendCustomMessage` — jangan re-introduce
// template-table di sini supaya scope tetap minimal.
// ─────────────────────────────────────────────────────────────────────────────

const DEFAULT_ENDPOINT = "https://api.fonnte.com/send";
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

export function sendCustomMessage(phone, message) {
  return sendWA(phone, message);
}

export const WhatsAppService = {
  formatWaPhone,
  sendWA,
  sendWAFireAndForget,
  sendCustomMessage,
};
