# Chat Pembeli di Website — Rencana Kerja

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pembeli yang memakai website Natalo (HP & komputer) bisa chat ke toko — pesan masuk ke NLCHAT sama seperti dari aplikasi — lengkap dengan tombol chat di kepala halaman, halaman `/chat` (HP), jendela chat pojok kanan bawah (komputer), tombol "Tanya soal pesanan ini" dan ikon chat di halaman produk.

**Architecture:** Backend sudah ada dan tidak diubah: `GET /api/chat/[chatId]`, `POST /api/chat/send`, `POST /api/chat/send-image`, `GET /api/chat/unread`, `GET /api/chat/config` (semua pakai sesi cookie website + CSRF same-origin). Pekerjaan ini murni sisi tampilan: (1) modul logika murni `lib/chat/web-client.ts` yang diuji `node:test`, (2) hook `useCustomerChat` yang memanggil API + mengambil pesan berkala tiap 4 detik selama terlihat, (3) komponen tampilan bersama yang dipakai halaman `/chat` dan jendela pojok, (4) titik masuk di Header, rincian pesanan, dan halaman produk.

**Tech Stack:** Next.js App Router (client components), React, Tailwind v4 (`@theme` di `app/globals.css`, warna `natalo-*`), font Nunito, `react-icons`, `tsx --test` (node:test).

**Acuan visual:** `docs/mockup/chat-web-pelanggan.html` (salinan juga di `NLCHAT/docs/mockup/`).

## Global Constraints

- Keputusan owner 2026-10-22: **1a** tombol chat di kepala halaman sebelah lonceng (bukan tombol mengambang); **2a** tombol "Konfirmasi via WhatsApp" di rincian pesanan TETAP ada, tombol chat di atasnya; **3a** wajib masuk akun — tamu melihat layar "Masuk dulu untuk chat"; **4a** komputer (≥ md / 768px) = jendela kecil pojok kanan bawah, HP = halaman `/chat` penuh.
- Gaya meniru chat aplikasi Natalo (`flutter_app/lib/widgets/chat/*`): gelembung pembeli `bg-natalo-500` teks putih, sudut 12 dengan sudut-ekor 4 (kanan atas); balasan toko putih + garis `#e2e8f0`, sudut-ekor kiri atas, nama staf di atas teks; catatan sistem di tengah bergaris putus-putus; kepala "Natalo Petshop & Aquarium" + status "Online" (titik hijau) / "Di luar jam operasional".
- Teks layar bahasa sehari-hari (dilarang: server, sinkron, error teknis mentah, kode status Inggris). Pesan galat dari API (`{error}`) sudah berbahasa Indonesia — tampilkan apa adanya.
- Sentuhan minimal 44px. Hanya mode terang. Jangan menambah dependensi baru.
- Komponen klien **tidak boleh** mengimpor nilai dari `lib/chat/core.ts` (memakai `node:crypto`) — hanya `import type`.
- Backend & NLCHAT tidak diubah di rencana ini. `main` Natalo berisi ±195 berkas setengah jadi milik owner → kerja di worktree, jangan sentuh berkas di luar daftar.
- Batasan yang disadari (sama seperti aplikasi): pengambilan berkala `?after=` hanya membawa pesan baru; perubahan status kartu yang sudah tampil terlihat saat chat dibuka ulang.

## Persiapan

- [ ] Worktree: `git worktree add .worktrees/chat-web -b feat/chat-web-pelanggan HEAD` dari `C:\Users\USER\Desktop\natalopetshopflutter`; `npm ci && npx prisma generate && npm test` → baseline hijau.
- [ ] Bila cabang `fix/nama-pembeli-chat` sudah digabung ke main sebelum mulai, buat worktree dari main terbaru.

## Peta berkas

| Berkas | Tanggung jawab |
|---|---|
| `lib/chat/web-client.ts` (baru) | logika murni: id pesan klien, gabung/urut pesan, kursor, label status kartu, tautan masuk |
| `tests/chat-web-client.test.ts` (baru) | tes logika murni |
| `components/chat/useCustomerChat.ts` (baru) | hook: muat, ambil berkala, muat lama, kirim teks/foto/konteks, coba lagi |
| `components/chat/useChatUnread.ts` (baru) | hook: angka belum-dibaca + status chat aktif |
| `components/chat/ChatIcon.tsx` (baru) | ikon gelembung 3 titik (sama dgn aplikasi) |
| `components/chat/ChatConversation.tsx` (baru) | tampilan bersama: kepala, daftar pesan, kotak tulis, layar masuk/mati |
| `components/chat/ChatMessageItem.tsx` (baru) | satu pesan: teks, foto, kartu pesanan, kartu produk, catatan sistem |
| `components/chat/ChatComposer.tsx` (baru) | kamera + kolom tulis (1–4 baris) + kirim |
| `components/chat/ChatLauncher.tsx` (baru) | penyedia global: buka chat (HP → `/chat`, komputer → jendela), render jendela pojok |
| `app/chat/page.tsx` (baru) | halaman chat penuh (HP; di komputer tetap jalan, lebar maks 720) |
| `app/layout.tsx` | pasang `ChatLauncher` |
| `components/Header.tsx` | tombol chat + angka belum-dibaca sebelah lonceng; sembunyikan kepala utama di `/chat` |
| `components/OrderDetailView.tsx` + `app/pesanan/[orderNumber]/page.tsx` | tombol "Tanya soal pesanan ini" (hanya pemilik pesanan) |
| `components/products/StickyAddToCartBar.tsx` | ikon chat menggantikan "Chat WA" saat chat aktif; WA tetap jadi cadangan saat chat mati |

---

### Task W1: Logika murni chat web

**Files:** Create `lib/chat/web-client.ts`, Test `tests/chat-web-client.test.ts`

**Interfaces (Produces):**
- `type WebChatMessage = CustomerMessage & { localState?: "sending" | "failed"; localKey: string }`
- `newClientMsgId(random?: () => string): string` — 8–64 karakter `[A-Za-z0-9_-]`, awalan `web_`.
- `mergeMessages(current: WebChatMessage[], incoming: CustomerMessage[]): WebChatMessage[]` — dedupe per `id`, lalu per `clientMsgId` (pesan server menggantikan versi "sending"/"failed" lokal dengan `clientMsgId` sama), urut `createdAt` naik (seri → urutan masuk).
- `toWebMessage(m: CustomerMessage): WebChatMessage` — `localKey = m.id ?? m.clientMsgId ?? \`t${m.createdAt}\``.
- `pendingMessage(input: { clientMsgId: string; text?: string; imagePreviewUrl?: string; now: number }): WebChatMessage`
- `markFailed(list, clientMsgId): WebChatMessage[]`
- `forwardCursor(list: WebChatMessage[], serverNextCursor: number | null, prev: number | null): number | null` — `serverNextCursor ?? max(createdAt pesan dari server, bukan lokal) ?? prev`.
- `orderCardLabel(order): { text: string; tone: "ok" | "warn" | "bad" | "info" }` — `paymentStatus PAID` atau `paymentProofStatus VERIFIED` → "Pembayaran terverifikasi"/ok; `REJECTED` → "Bukti transfer ditolak"/bad; `PENDING_REVIEW` → "Bukti sedang dicek"/warn; selain itu "Menunggu pembayaran"/info bila `paymentStatus` UNPAID/PENDING, lainnya "Pesanan"/info.
- `chatHref(ctx?: { orderNumber?: string; productId?: string }): string` — `/chat`, `/chat?order=ORD-…`, `/chat?product=<id>` (di-encode).
- `parseChatContext(search: URLSearchParams): { type: "order"; orderNumber: string } | { type: "product"; productId: string } | null` — panjang maks 80, hanya `[A-Za-z0-9_-]`.

- [ ] **Step 1: Tes gagal** — `tests/chat-web-client.test.ts`:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import {
  chatHref, forwardCursor, markFailed, mergeMessages, newClientMsgId,
  orderCardLabel, parseChatContext, pendingMessage, toWebMessage,
} from "@/lib/chat/web-client";

test("newClientMsgId lolos aturan server", () => {
  const id = newClientMsgId();
  assert.match(id, /^web_[A-Za-z0-9_-]{4,60}$/);
  assert.ok(id.length >= 8 && id.length <= 64);
  assert.notEqual(newClientMsgId(), id);
});

test("pesan server menggantikan pesan lokal dengan clientMsgId sama, urut waktu", () => {
  const local = pendingMessage({ clientMsgId: "web_a1b2c3d4", text: "halo", now: 500 });
  const merged = mergeMessages([local], [
    { id: "m2", senderRole: "staff", type: "text", text: "hai", createdAt: 600 },
    { id: "m1", clientMsgId: "web_a1b2c3d4", senderRole: "customer", type: "text", text: "halo", createdAt: 510 },
  ]);
  assert.deepEqual(merged.map((m) => m.localKey), ["m1", "m2"]);
  assert.equal(merged[0].localState, undefined);
});

test("gabung dua kali tidak menggandakan pesan", () => {
  const a = [{ id: "m1", senderRole: "customer" as const, type: "text" as const, text: "x", createdAt: 1 }];
  const once = mergeMessages([], a);
  assert.equal(mergeMessages(once, a).length, 1);
});

test("markFailed hanya menandai pesan lokal yang cocok", () => {
  const list = [pendingMessage({ clientMsgId: "web_aaaa1111", text: "a", now: 1 }), toWebMessage({ id: "m9", senderRole: "staff", type: "text", createdAt: 2 })];
  const out = markFailed(list, "web_aaaa1111");
  assert.equal(out[0].localState, "failed");
  assert.equal(out[1].localState, undefined);
});

test("kursor maju: pakai nextCursor server, lalu createdAt server terbesar, abaikan pesan lokal", () => {
  const list = [toWebMessage({ id: "m1", senderRole: "staff", type: "text", createdAt: 100 }), pendingMessage({ clientMsgId: "web_bbbb2222", text: "b", now: 999 })];
  assert.equal(forwardCursor(list, 150, 50), 150);
  assert.equal(forwardCursor(list, null, 50), 100);
  assert.equal(forwardCursor([], null, 50), 50);
});

test("label kartu pesanan bahasa sehari-hari", () => {
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentStatus: "PAID" }), { text: "Pembayaran terverifikasi", tone: "ok" });
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentProofStatus: "REJECTED" }), { text: "Bukti transfer ditolak", tone: "bad" });
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentProofStatus: "PENDING_REVIEW" }), { text: "Bukti sedang dicek", tone: "warn" });
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentStatus: "UNPAID" }), { text: "Menunggu pembayaran", tone: "info" });
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentStatus: "PAID", paymentProofStatus: "REJECTED" }), { text: "Pembayaran terverifikasi", tone: "ok" });
});

test("tautan & konteks chat aman", () => {
  assert.equal(chatHref(), "/chat");
  assert.equal(chatHref({ orderNumber: "ORD-1" }), "/chat?order=ORD-1");
  assert.equal(chatHref({ productId: "p_1" }), "/chat?product=p_1");
  assert.deepEqual(parseChatContext(new URLSearchParams("order=ORD-20261022-5LLQZS")), { type: "order", orderNumber: "ORD-20261022-5LLQZS" });
  assert.deepEqual(parseChatContext(new URLSearchParams("product=cm9abc")), { type: "product", productId: "cm9abc" });
  assert.equal(parseChatContext(new URLSearchParams("order=<script>")), null);
  assert.equal(parseChatContext(new URLSearchParams("")), null);
});
```

- [ ] **Step 2:** `npx tsx --test tests/chat-web-client.test.ts` → FAIL (modul belum ada).
- [ ] **Step 3: Implementasi** `lib/chat/web-client.ts`:

```ts
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
```
Cek nilai `paymentStatus` sebenarnya di `prisma/schema.prisma` (enum PaymentStatus) dan tambahkan nilai "belum dibayar" lain bila ada.

- [ ] **Step 4:** tes → PASS; `npx tsc --noEmit`.
- [ ] **Step 5: Mutasi** — hapus cabang `clientIndex` di `mergeMessages` → tes "pesan server menggantikan" MERAH. Kembalikan.
- [ ] **Step 6: Commit** — `feat(chat-web): logika murni chat pembeli di website` (+ trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

### Task W2: Hook data chat

**Files:** Create `components/chat/useCustomerChat.ts`, `components/chat/useChatUnread.ts`

**Interfaces:**
- Consumes: semua dari W1.
- Produces `useCustomerChat(opts: { enabled: boolean; context: ChatContext | null })` →
  `{ status: "loading" | "guest" | "ready" | "disabled" | "error"; messages: WebChatMessage[]; online: boolean | null; hasOlder: boolean; loadingOlder: boolean; loadOlder(): Promise<void>; sendText(text: string): Promise<void>; sendImage(file: File): Promise<void>; retry(clientMsgId: string): Promise<void>; pendingContext: ChatContext | null; clearContext(): void; errorText: string | null }`
- Produces `useChatUnread(): { loggedIn: boolean | null; chatEnabled: boolean; unread: number; refresh(): void }`

Perilaku (wajib):
1. Saat `enabled`: `GET /api/auth/me` → 401/tanpa `id` → `status:"guest"`. Ada → `chatId = "cust_" + id`.
2. Paralel `GET /api/chat/config` → `chatEnabled:false` → `status:"disabled"`; simpan `online`.
3. Muat awal `GET /api/chat/${chatId}?dir=older` (halaman terbaru, tanpa `before`); `hasOlder = prevCursor !== null`; simpan `prevCursor`; `cursor = forwardCursor(messages, null, null)`.
4. Ambil berkala tiap **4000 ms** hanya saat `document.visibilityState === "visible"` dan tidak ada permintaan berjalan: `GET ?after=${cursor}` → `mergeMessages`; perbarui kursor. Setiap 5 putaran, ulang `GET /api/chat/config` (status online / dimatikan). Berhenti saat komponen dilepas.
5. `loadOlder`: `GET ?dir=older&before=${prevCursor}` → gabung.
6. `sendText(text)`: `clientMsgId = newClientMsgId()`; tambahkan `pendingMessage`; `POST /api/chat/send` body `{ text, clientMsgId, context?: pendingContext }` (konteks hanya dikirim di pesan pertama lalu `clearContext()`); `credentials:"same-origin"`, header `content-type: application/json`. Gagal (bukan 2xx) → `markFailed` + `errorText` = `json.error` atau "Pesan belum terkirim. Coba lagi."; sukses → langsung ambil berkala sekali.
7. Konteks pesanan (`type:"order"`) **dikirim otomatis** sekali saat chat terbuka dengan konteks itu (body `{ clientMsgId, context }` tanpa teks, sama seperti aplikasi), lalu `clearContext()`. Konteks produk menunggu pesan pertama yang diketik (ditampilkan sebagai bilah "Menanyakan produk").
8. `sendImage(file)`: tolak di klien bila bukan jpeg/png/webp atau > 5 MB (pesan: "Foto harus JPG/PNG/WEBP, maksimal 5 MB."); pratinjau `URL.createObjectURL`; `POST /api/chat/send-image` multipart `file` + `clientMsgId`; batas tunggu 90 detik (`AbortController`); lepaskan URL objek setelah pesan server masuk.
9. `retry(clientMsgId)`: kirim ulang dengan `clientMsgId` yang SAMA (server idempoten).
10. `useChatUnread`: `GET /api/auth/me` + `GET /api/chat/config`; bila masuk & aktif, `GET /api/chat/unread` tiap 30 detik saat terlihat, dan saat event `window` `"auth-updated"` / `"chat-read"`. `useCustomerChat` memicu `window.dispatchEvent(new Event("chat-read"))` setelah muat awal.

- [ ] **Step 1:** tulis kedua hook sesuai perilaku di atas (tanpa dependensi baru; `fetch` biasa).
- [ ] **Step 2:** `npx tsc --noEmit` + `npx eslint components/chat` bersih (`react-hooks/exhaustive-deps` dipatuhi).
- [ ] **Step 3: Commit** — `feat(chat-web): hook data chat pembeli`.

(Tidak ada tes unit: logika keputusan sudah di W1; hook diuji di peramban pada W6.)

### Task W3: Tampilan percakapan bersama

**Files:** Create `components/chat/ChatIcon.tsx`, `ChatMessageItem.tsx`, `ChatComposer.tsx`, `ChatConversation.tsx`

**Interfaces:**
- `ChatIcon({ className })` — SVG gelembung + 3 titik (`stroke="currentColor"`).
- `ChatConversation({ variant: "page" | "window", context: ChatContext | null, onBack?: () => void, onMinimize?: () => void, onClose?: () => void })` — memakai `useCustomerChat`.

Aturan tampilan (lihat mockup):
- Kepala: tinggi 64 (`window`: 58), putih, garis bawah `#e2e8f0`. `page` → tombol kembali (44×44, `aria-label="Kembali"`); `window` → tombol "Kecilkan" (−) & "Tutup" (×) 44×44. Judul "Natalo Petshop & Aquarium" 17px/800 (window 15.5px). Di bawahnya status: `online` → titik hijau `#22c55e` + "Online" (hijau `#15803d`, 11px/800); `false` → titik abu + "Di luar jam operasional".
- Daftar: latar `#f8fafc`, padding 12, `aria-live="polite"`. Penanda hari ("Hari ini", "Kemarin", "22 Oktober 2026") di antara pesan beda tanggal (zona WIB, `Intl.DateTimeFormat("id-ID", { timeZone: "Asia/Jakarta" })`). Gulir otomatis ke bawah saat buka & saat pesan baru masuk bila pengguna sedang di dasar; tombol "Muat pesan sebelumnya" di atas bila `hasOlder`.
- `ChatMessageItem`:
  - `type:"system"` (atau `auto`) → catatan tengah, putih, garis putus `#cbd5e1`, 12.5px `text-slate-600`.
  - pembeli (`senderRole:"customer"`) → kanan, `bg-natalo-500 text-white`, `rounded-xl rounded-tr` (ekor 4px), maks 78%; jam 10px saja (proyeksi pembeli tidak membawa tanda "dibaca staf", jadi tanpa centang); `sending` → "Mengirim…"; `failed` → teks merah "Belum terkirim · Coba lagi" yang bisa ditekan (tinggi 44px).
  - toko → kiri, putih, `border border-slate-200`, `rounded-xl rounded-tl`; nama staf (`senderName`) 11.5px/800 `text-natalo-500`.
  - `image` → foto maks 240px lebar, sudut 12, klik buka di tab baru (`imagePreviewUrl` saat mengirim).
  - `order_context` → kartu kanan (dari pembeli) lebar 82%, putih, garis, sudut 16: "Pesanan", nomor + `Rp` (format `id-ID`), "N barang", pil `orderCardLabel` (ok `bg-green-100 text-green-700`, warn `bg-amber-100 text-amber-800`, bad `bg-red-100 text-red-700`, info `bg-natalo-50 text-natalo-700`), tautan "Lihat pesanan" → `/pesanan/{orderNumber}`.
  - `product`/`product_context` → kartu produk kecil (foto 48, nama 2 baris, harga) tautan ke `/products/{slug}` bila ada `slug`.
  - `replyTo` → kutipan kecil di dalam gelembung (garis kiri 3px).
  - Teks: `whitespace-pre-wrap break-words`; tautan http(s) dijadikan `<a target="_blank" rel="noopener noreferrer">` (tanpa `dangerouslySetInnerHTML`).
- `ChatComposer`: kamera (44, `aria-label="Kirim foto"`, `<input type="file" accept="image/jpeg,image/png,image/webp">` tersembunyi), `textarea` 1–4 baris tumbuh otomatis, latar `#f8fafc`, sudut penuh, placeholder "Tulis pesan…", maks 4000 karakter; tombol kirim bulat 44 `bg-natalo-500` (`aria-label="Kirim"`) hanya aktif bila ada teks. Komputer: Enter = kirim, Shift+Enter = baris baru; HP (layar sentuh) Enter = baris baru. Saat mengetik di HP tambahkan class `nat-keyboard-open` ke `body` lewat `focus`/`blur` (konvensi yang sudah ada).
- Bilah konteks produk di atas kotak tulis: "Menanyakan produk" + nama, tombol × (44) memanggil `clearContext`.
- Layar `guest`: ikon besar, "Masuk dulu untuk chat", "Supaya toko tahu pesanan dan riwayat belanjamu, chat hanya bisa dipakai setelah masuk akun.", tombol "Masuk" → `/member/login?redirect=` + path sekarang (termasuk query konteks), tombol "Daftar akun baru" → `/member/register`.
- Layar `disabled`: bilah kuning "Chat sedang tidak bisa dipakai. Hubungi kami lewat WhatsApp dulu ya." + tombol "Chat lewat WhatsApp" memakai nomor WA yang sama dengan `StickyAddToCartBar`/`OrderDetailView` (cari sumbernya: `waNumber`/`NEXT_PUBLIC_WA_NUMBER` — pakai helper yang sudah ada, jangan menulis nomor baru).
- Layar kosong (`ready` tanpa pesan): "Mulai percakapan dengan Natalo Petshop" / "Tim kami siap bantu pertanyaan produk & pesananmu."
- `errorText` tampil sebagai toast/teks kecil merah di atas kotak tulis, hilang saat mengetik.

- [ ] **Step 1:** buat keempat komponen ("use client").
- [ ] **Step 2:** `npx tsc --noEmit` + `npx eslint components/chat`.
- [ ] **Step 3: Commit** — `feat(chat-web): tampilan percakapan chat pembeli`.

### Task W4: Halaman `/chat` + peluncur global + jendela komputer

**Files:** Create `app/chat/page.tsx`, `components/chat/ChatLauncher.tsx`; Modify `app/layout.tsx`

**Interfaces:**
- `ChatLauncher` (client, dipasang sekali di `app/layout.tsx` di dalam `<body>` setelah konten, di luar `/admin`): mendengar `window` event `"open-chat"` (`CustomEvent<{ orderNumber?: string; productId?: string }>`). Fungsi bantu diekspor `openChat(ctx?)` yang mengirim event itu.
  - Lebar `< 768px` → `router.push(chatHref(ctx))`.
  - `≥ 768px` → tampilkan jendela tetap `fixed right-6 bottom-6 z-[90] w-[370px] h-[min(560px,calc(100vh-120px))] rounded-[18px] shadow-[0_18px_50px_rgba(15,40,70,.28)] border border-slate-200 bg-white` berisi `ChatConversation variant="window"`. Konteks baru menggantikan konteks lama. "Kecilkan" = sembunyikan jendela (status chat tetap di memori), "Tutup" = sembunyikan + buang konteks. `Escape` menutup. Fokus pindah ke kolom tulis saat dibuka.
  - Jendela tidak dirender di `/chat`, `/admin*`, `/checkout*`, `/member/login*`.
- `app/chat/page.tsx`: client page; `parseChatContext(useSearchParams())`; `ChatConversation variant="page"` setinggi layar (`h-[100dvh]` dikurangi tidak ada bilah bawah), lebar maks 720 di tengah pada komputer; `onBack` = `router.back()` bila ada riwayat, kalau tidak `router.push("/")`. Judul halaman (`metadata` lewat `layout.tsx` kecil di `app/chat/`) "Chat Natalo Petshop".
- Bilah bawah HP & kepala utama situs disembunyikan di `/chat`: tambahkan `/chat` ke `shouldHideBottomNav` (`lib/navigation`) dan ke kondisi Header yang menyembunyikan kepala utama (ikuti pola halaman lain yang memakai kepala sendiri).

- [ ] **Step 1:** buat berkas + pemasangan di layout.
- [ ] **Step 2:** `npx tsc --noEmit`, `npx eslint app/chat components/chat app/layout.tsx lib/navigation*`.
- [ ] **Step 3: Commit** — `feat(chat-web): halaman /chat dan jendela chat di komputer`.

### Task W5: Titik masuk (kepala, pesanan, produk)

**Files:** Modify `components/Header.tsx`, `components/OrderDetailView.tsx`, `app/pesanan/[orderNumber]/page.tsx`, `components/products/StickyAddToCartBar.tsx`

- **Header** (di `<div>` aksi kanan, tepat SEBELUM `{showBell && <NotificationBell compact />}`, sekitar baris 376): tombol `h-10 w-10 rounded-full` (area sentuh 44 lewat padding/`min-h-11`), `aria-label` "Chat dengan toko" (+ ", N pesan belum dibaca" bila ada), ikon `ChatIcon`, latar `bg-natalo-50 text-natalo-600` saat ada belum-dibaca; angka merah (`bg-red-500`, 10px/800, maks "99+", garis putih 2px) di kanan atas. Klik → `openChat()`. Ditampilkan saat `!isAuthPage` dan `useChatUnread().chatEnabled` (tamu juga melihat — layar masuk akun muncul di dalam chat). Tidak tampil di `/chat`.
- **Rincian pesanan:** `app/pesanan/[orderNumber]/page.tsx` meneruskan `canChat={isOwner}` ke `OrderDetailView`. Di `OrderDetailView` tambahkan prop `canChat?: boolean` dan, bila `canChat`, tombol penuh `rounded-full bg-natalo-500 text-white py-3 font-black` "Tanya soal pesanan ini" (ikon chat) → `openChat({ orderNumber: order.orderNumber })`. Letak: tepat di atas `<OrderFollowUpCard order={order} />` (selalu terlihat, semua status). Tombol "Konfirmasi via WhatsApp" tidak diubah.
- **Produk (HP):** `StickyAddToCartBar` membaca `useChatUnread().chatEnabled`; bila aktif, ganti `ExternalLink` "Chat WA" dengan tombol persegi 44×44 `rounded-xl border` ikon chat `text-natalo-600`, `aria-label="Tanya produk ini"` → `openChat({ productId })`. Tambahkan prop `productId: string` (teruskan dari pemanggil di `app/products/[slug]/page.tsx`). Bila chat mati → tombol "Chat WA" lama tetap.

- [ ] **Step 1:** ubah keempat berkas.
- [ ] **Step 2:** `npx tsc --noEmit`, `npx eslint` berkas tersentuh, `npm test`.
- [ ] **Step 3: Penyisiran teks awam** semua string baru.
- [ ] **Step 4: Commit** — `feat(chat-web): tombol chat di kepala, rincian pesanan, dan halaman produk`.

### Task W6: Uji di peramban

- [ ] **Step 1:** `preview_start` dengan konfigurasi `toko-pwa` (`.claude/launch.json`, port 3000) dari worktree (salin `.env.local` milik owner ke worktree bila diperlukan — JANGAN di-commit). Catatan: data chat/pesanan memakai basis data & Firestore yang dikonfigurasi `.env.local` — pastikan dengan owner apakah itu data produksi sebelum mengirim pesan uji.
- [ ] **Step 2:** sebagai tamu: tombol chat tampil di kepala → layar "Masuk dulu untuk chat" (HP: `/chat`; komputer: jendela). Tanpa galat konsol.
- [ ] **Step 3:** login **dilakukan owner sendiri** di panel peramban (Claude tidak mengetik kata sandi). Lalu: kirim teks, kirim foto, buka dari rincian pesanan (kartu pesanan otomatis terkirim), buka dari produk (bilah "Menanyakan produk"), balasan staf dari NLCHAT muncul ≤ 5 detik, angka belum-dibaca di kepala hilang setelah chat dibuka.
- [ ] **Step 4:** ukuran HP (375×812) dan komputer: tidak ada geser samping, sentuhan ≥ 44px, keyboard tidak menutupi kotak tulis.
- [ ] **Step 5:** tangkapan layar per butir → laporan ke owner; minta izin gabung/kirim/pasang.

## Urutan rilis
Gabung ke `main` Natalo → push → Vercel. Tidak ada perubahan basis data/aturan Firestore; aplikasi HP & NLCHAT tidak perlu rilis.
