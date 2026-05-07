import { prisma } from "@/lib/prisma";

type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();

export function checkChatRateLimit(
  key: string,
  maxAttempts = 20,
  windowMs = 60_000
) {
  const now = Date.now();
  const bucket = buckets.get(key);

  if (!bucket || bucket.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return { ok: true, remaining: maxAttempts - 1 };
  }

  if (bucket.count >= maxAttempts) {
    return {
      ok: false,
      retryAfter: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)),
    };
  }

  bucket.count += 1;
  return { ok: true, remaining: maxAttempts - bucket.count };
}

export async function getOrCreateCustomerThread(userId: string) {
  return prisma.chatThread.upsert({
    where: { userId },
    create: { userId },
    update: {},
  });
}

export function normalizeChatMessage(content: unknown) {
  const text = String(content ?? "").trim();
  if (!text) throw new Error("Pesan tidak boleh kosong.");
  if (text.length > 1000) throw new Error("Pesan maksimal 1000 karakter.");
  return text;
}
