"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { CustomerMessage } from "@/lib/chat/core";
import {
  forwardCursor,
  markFailed,
  mergeMessages,
  newClientMsgId,
  pendingMessage,
  type ChatContext,
  type WebChatMessage,
} from "@/lib/chat/web-client";
import { forgetChatConfig, getChatConfig } from "./chatConfig";

const POLL_MS = 4000;
// Sepi 60 detik (tanpa pesan baru / kiriman) → ambil tiap 10 detik (hemat baca data).
const POLL_IDLE_MS = 10_000;
const IDLE_AFTER_MS = 60_000;
const CONFIG_EVERY_ROUNDS = 5;
const ANNOUNCE_MAX = 100;
const IMAGE_TIMEOUT_MS = 90_000;
const IMAGE_MAX_BYTES = 5 * 1024 * 1024;
const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"];

const TEXT_FAIL = "Pesan belum terkirim. Coba lagi.";
const IMAGE_FAIL = "Foto belum terkirim. Coba lagi.";
const IMAGE_INVALID = "Foto harus JPG/PNG/WEBP, maksimal 5 MB.";
const LOAD_FAIL = "Chat belum bisa dimuat. Coba lagi sebentar lagi.";
const OLDER_FAIL = "Pesan lama belum bisa dimuat. Coba lagi.";

export type CustomerChatStatus = "loading" | "guest" | "ready" | "disabled" | "error";

type Outgoing =
  | { kind: "text"; text?: string; context?: ChatContext }
  | { kind: "image"; file: File };

type PageJson = {
  messages?: CustomerMessage[];
  prevCursor?: number | null;
  nextCursor?: number | null;
  error?: string;
};

// Teks galat untuk pembeli: teks server hanya dipakai bila kodenya membawa
// bahasa Indonesia (400/413/415/429/503); selain itu pakai teks umum.
// 400 bisa membawa teks teknis ("Invalid JSON", "clientMsgId …") → teks umum.
const FRIENDLY_STATUSES = [400, 413, 415, 429, 503];
const TECHNICAL_400 = [/invalid json/i, /clientmsgid/i];
async function readErrorText(res: Response, fallback: string): Promise<string> {
  if (!FRIENDLY_STATUSES.includes(res.status)) return fallback;
  try {
    const json = (await res.json()) as { error?: unknown };
    const err = json.error;
    if (typeof err !== "string" || !err) return fallback;
    if (res.status === 400 && TECHNICAL_400.some((re) => re.test(err))) return fallback;
    return err;
  } catch {
    return fallback;
  }
}

// Kalimat singkat untuk pembaca layar saat pesan toko masuk.
function announceText(m: CustomerMessage): string {
  const raw =
    m.text?.trim() ||
    (m.type === "image" ? "Foto" : m.type === "product" || m.type === "product_context" ? "Info produk" : "");
  const preview = raw.length > ANNOUNCE_MAX ? `${raw.slice(0, ANNOUNCE_MAX - 1)}…` : raw;
  const who = m.senderName?.trim() || "toko";
  return preview ? `Pesan baru dari ${who}: ${preview}` : `Pesan baru dari ${who}`;
}

function contextKey(c: ChatContext | null): string {
  if (!c) return "";
  return `${c.type}:${c.type === "order" ? c.orderNumber : c.productId}`;
}

function contextFromKey(key: string): ChatContext | null {
  const i = key.indexOf(":");
  if (i < 0) return null;
  const type = key.slice(0, i);
  const value = key.slice(i + 1);
  if (type === "order") return { type: "order", orderNumber: value };
  if (type === "product") return { type: "product", productId: value };
  return null;
}

async function readJson<T>(res: Response): Promise<T | null> {
  try {
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export function useCustomerChat(opts: {
  enabled: boolean;
  context: ChatContext | null;
  /** Dipanggil setelah konteks terkirim (otomatis / ikut pesan pertama) atau dibatalkan. */
  onContextConsumed?: () => void;
}): {
  status: CustomerChatStatus;
  messages: WebChatMessage[];
  online: boolean | null;
  hasOlder: boolean;
  loadingOlder: boolean;
  loadOlder(): Promise<void>;
  sendText(text: string): Promise<void>;
  sendImage(file: File): Promise<void>;
  retry(clientMsgId: string): Promise<void>;
  pendingContext: ChatContext | null;
  clearContext(): void;
  errorText: string | null;
  /** Pengumuman pembaca layar untuk pesan toko yang baru masuk. */
  announcement: { id: number; text: string } | null;
} {
  const { enabled, context, onContextConsumed } = opts;

  const [status, setStatus] = useState<CustomerChatStatus>("loading");
  const [messages, setMessages] = useState<WebChatMessage[]>([]);
  const [online, setOnline] = useState<boolean | null>(null);
  const [hasOlder, setHasOlder] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [pendingContext, setPendingContext] = useState<ChatContext | null>(context);
  const [errorText, setErrorText] = useState<string | null>(null);
  const [chatId, setChatId] = useState<string | null>(null);
  const [announcement, setAnnouncement] = useState<{ id: number; text: string } | null>(null);

  const mountedRef = useRef(true);
  const messagesRef = useRef<WebChatMessage[]>([]);
  const cursorRef = useRef<number | null>(null);
  const prevCursorRef = useRef<number | null>(null);
  const pollBusyRef = useRef(false);
  const olderBusyRef = useRef(false);
  const roundRef = useRef(0);
  const pollAgainRef = useRef(false);
  const pendingContextRef = useRef<ChatContext | null>(context);
  const outgoingRef = useRef(new Map<string, Outgoing>());
  const previewUrlsRef = useRef(new Map<string, string>());
  const autoSentRef = useRef<string | null>(null);
  const chatIdRef = useRef<string | null>(null);
  const lastActivityRef = useRef(0);
  const wakeRef = useRef<(() => void) | null>(null);
  const consumedRef = useRef(onContextConsumed);
  useEffect(() => {
    consumedRef.current = onContextConsumed;
  }, [onContextConsumed]);

  // Hanya saat masih terpasang: halaman /chat yang sudah ditinggal tidak boleh
  // mengganti alamat lagi (router.replace) setelah kiriman telat selesai.
  const notifyConsumed = useCallback(() => {
    if (mountedRef.current) consumedRef.current?.();
  }, []);

  // Ada kegiatan (kirim pesan) → ambil berkala kembali cepat.
  const markActive = useCallback(() => {
    lastActivityRef.current = Date.now();
    wakeRef.current?.();
  }, []);

  useEffect(() => {
    mountedRef.current = true;
    const previews = previewUrlsRef.current;
    return () => {
      mountedRef.current = false;
      for (const url of previews.values()) URL.revokeObjectURL(url);
      previews.clear();
    };
  }, []);

  // Terapkan perubahan daftar pesan; lepaskan URL pratinjau yang pesannya sudah
  // digantikan salinan server (mergeMessages membuang imagePreviewUrl-nya).
  const applyMessages = useCallback((update: (cur: WebChatMessage[]) => WebChatMessage[]) => {
    const next = update(messagesRef.current);
    messagesRef.current = next;
    setMessages(next);
    const previews = previewUrlsRef.current;
    for (const [clientMsgId, url] of previews) {
      const m = next.find((x) => x.clientMsgId === clientMsgId);
      if (m && !m.imagePreviewUrl) {
        URL.revokeObjectURL(url);
        previews.delete(clientMsgId);
      }
    }
  }, []);

  const setContext = useCallback((ctx: ChatContext | null) => {
    pendingContextRef.current = ctx;
    setPendingContext(ctx);
  }, []);

  // Bandingkan konteks menurut isinya (bukan identitas objek).
  const ctxKey = contextKey(context);
  useEffect(() => {
    autoSentRef.current = null;
    setContext(contextFromKey(ctxKey));
  }, [ctxKey, setContext]);

  // Sesi habis di tengah jalan → layar "masuk dulu"; polling ikut berhenti.
  const goGuest = useCallback(() => {
    if (mountedRef.current) setStatus("guest");
  }, []);

  // Dibatalkan pembeli (tombol ×) atau ikut terkirim bersama pesan pertama.
  const clearContext = useCallback(() => {
    const had = pendingContextRef.current !== null;
    setContext(null);
    if (had) notifyConsumed();
  }, [setContext, notifyConsumed]);

  // true = chat aktif, false = dimatikan, null = tidak tahu (gagal ambil).
  // Hasil disimpan 5 menit (chatConfig.ts) supaya tidak membaca ulang terus.
  const checkConfig = useCallback(async (): Promise<boolean | null> => {
    const cfg = await getChatConfig();
    if (!cfg || !mountedRef.current) return null;
    if (cfg.online !== null) setOnline(cfg.online);
    return cfg.chatEnabled;
  }, []);

  // ── Muat awal ────────────────────────────────────────────────────────
  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;
    setStatus("loading");
    setErrorText(null);

    (async () => {
      try {
        // Setelan chat dibaca hanya setelah jelas sudah masuk akun (tamu: tanpa baca data).
        const meRes = await fetch("/api/auth/me", { cache: "no-store", credentials: "same-origin" });
        if (cancelled) return;
        const me = meRes.ok ? await readJson<{ id?: string }>(meRes) : null;
        if (cancelled) return;
        if (!me?.id) {
          setStatus("guest");
          return;
        }
        const cfg = await checkConfig();
        if (cancelled) return;
        if (cfg === false) {
          setStatus("disabled");
          return;
        }
        const id = `cust_${me.id}`;
        const res = await fetch(`/api/chat/${encodeURIComponent(id)}?dir=older`, {
          cache: "no-store",
          credentials: "same-origin",
        });
        if (cancelled) return;
        if (!res.ok) {
          if (res.status === 401) setStatus("guest");
          else {
            setErrorText(await readErrorText(res, LOAD_FAIL));
            if (!cancelled) setStatus("error");
          }
          return;
        }
        const json = await readJson<PageJson>(res);
        if (cancelled) return;
        if (res.status === 401) {
          setStatus("guest");
          return;
        }
        if (!res.ok || !json) {
          setErrorText(res.ok ? LOAD_FAIL : await readErrorText(res, LOAD_FAIL));
          setStatus("error");
          return;
        }
        const prev = json.prevCursor ?? null;
        prevCursorRef.current = prev;
        setHasOlder(prev !== null);
        messagesRef.current = [];
        applyMessages((cur) => mergeMessages(cur, json.messages ?? []));
        cursorRef.current = forwardCursor(messagesRef.current, null, null);
        chatIdRef.current = id;
        lastActivityRef.current = Date.now();
        setChatId(id);
        setStatus("ready");
        window.dispatchEvent(new Event("chat-read"));
      } catch {
        if (!cancelled) {
          setErrorText(LOAD_FAIL);
          setStatus("error");
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [enabled, checkConfig, applyMessages]);

  // ── Ambil berkala ────────────────────────────────────────────────────
  const pollOnce = useCallback(async (): Promise<void> => {
    const id = chatIdRef.current;
    if (!id) return;
    if (pollBusyRef.current) {
      pollAgainRef.current = true; // ulangi begitu putaran berjalan selesai
      return;
    }
    pollBusyRef.current = true;
    try {
      const after = cursorRef.current;
      const qs = after === null ? "" : `?after=${after}`;
      const res = await fetch(`/api/chat/${encodeURIComponent(id)}${qs}`, {
        cache: "no-store",
        credentials: "same-origin",
      });
      if (res.status === 401) {
        goGuest();
        return;
      }
      if (res.ok) {
        const json = await readJson<PageJson>(res);
        if (json && mountedRef.current) {
          const incoming = json.messages ?? [];
          if (incoming.some((m) => m.senderRole !== "customer")) {
            window.dispatchEvent(new Event("chat-read"));
          }
          // Pesan yang benar-benar baru (belum ada di layar), bukan salinan ulang.
          const known = new Set<string>();
          for (const m of messagesRef.current) {
            known.add(m.localKey);
            if (m.clientMsgId) known.add(m.clientMsgId);
          }
          const fresh = incoming.filter(
            (m) => !(m.id && known.has(m.id)) && !(m.clientMsgId && known.has(m.clientMsgId)),
          );
          if (fresh.length > 0) lastActivityRef.current = Date.now();
          const fromStaff = fresh.filter((m) => m.senderRole === "staff");
          if (fromStaff.length > 0) {
            const text = fromStaff.map(announceText).join(". ");
            setAnnouncement((prev) => ({ id: (prev?.id ?? 0) + 1, text }));
          }
          applyMessages((cur) => mergeMessages(cur, incoming));
          cursorRef.current = forwardCursor(messagesRef.current, json.nextCursor ?? null, cursorRef.current);
        }
      }
      roundRef.current += 1;
      if (roundRef.current % CONFIG_EVERY_ROUNDS === 0) {
        const cfg = await checkConfig();
        if (cfg === false && mountedRef.current) setStatus("disabled");
      }
    } catch {
      /* jaringan putus sesaat; putaran berikutnya mencoba lagi */
    } finally {
      pollBusyRef.current = false;
      if (pollAgainRef.current && mountedRef.current) {
        pollAgainRef.current = false;
        void pollOnce();
      }
    }
  }, [applyMessages, checkConfig, goGuest]);

  useEffect(() => {
    if (status !== "ready" || !enabled) return;
    let stopped = false;
    let gen = 0;
    let timer: number | undefined;

    let delay = POLL_MS;

    // Rantai setTimeout: satu putaran selesai dulu baru dijadwalkan berikutnya.
    // Jeda 4 detik; sepi 60 detik (tanpa pesan baru/kiriman) → 10 detik.
    const schedule = (myGen: number) => {
      delay = Date.now() - lastActivityRef.current >= IDLE_AFTER_MS ? POLL_IDLE_MS : POLL_MS;
      timer = window.setTimeout(() => void tick(myGen), delay);
    };
    const tick = async (myGen: number) => {
      timer = undefined;
      if (document.visibilityState === "visible") await pollOnce();
      if (stopped || myGen !== gen) return;
      schedule(myGen);
    };
    const restart = () => {
      gen += 1;
      window.clearTimeout(timer);
      void tick(gen);
    };
    const onVisible = () => {
      if (document.visibilityState === "visible") {
        lastActivityRef.current = Date.now();
        restart();
      }
    };
    // Dari markActive(): bila sedang menunggu jeda panjang, jadwalkan ulang ke
    // 4 detik tanpa ambil tambahan (pengirim memicu pollOnce sendiri). Bila
    // putaran sedang berjalan (timer kosong), putaran itu memakai jeda baru.
    wakeRef.current = () => {
      if (stopped || timer === undefined || delay <= POLL_MS) return;
      gen += 1;
      window.clearTimeout(timer);
      schedule(gen);
    };

    void tick(gen);
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      stopped = true;
      wakeRef.current = null;
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [status, enabled, pollOnce]);

  // ── Pesan lama ───────────────────────────────────────────────────────
  const loadOlder = useCallback(async () => {
    const id = chatIdRef.current;
    const before = prevCursorRef.current;
    if (!id || before === null || olderBusyRef.current) return;
    olderBusyRef.current = true;
    setLoadingOlder(true);
    try {
      const res = await fetch(`/api/chat/${encodeURIComponent(id)}?dir=older&before=${before}`, {
        cache: "no-store",
        credentials: "same-origin",
      });
      if (res.status === 401) {
        goGuest();
        return;
      }
      if (!res.ok) {
        const text = await readErrorText(res, OLDER_FAIL);
        if (mountedRef.current) setErrorText(text);
        return;
      }
      const json = await readJson<PageJson>(res);
      if (!mountedRef.current) return;
      if (!json) {
        setErrorText(OLDER_FAIL);
        return;
      }
      const prev = json.prevCursor ?? null;
      prevCursorRef.current = prev;
      setHasOlder(prev !== null);
      applyMessages((cur) => mergeMessages(cur, json.messages ?? []));
    } catch {
      if (mountedRef.current) setErrorText(OLDER_FAIL);
    } finally {
      olderBusyRef.current = false;
      if (mountedRef.current) setLoadingOlder(false);
    }
  }, [applyMessages, goGuest]);

  // ── Kirim ────────────────────────────────────────────────────────────
  const deliver = useCallback(
    async (clientMsgId: string, out: Outgoing, track: boolean): Promise<boolean> => {
      let timeout: number | undefined;
      try {
        let res: Response;
        if (out.kind === "text") {
          const body: Record<string, unknown> = { clientMsgId };
          if (out.text) body.text = out.text;
          if (out.context) body.context = out.context;
          res = await fetch("/api/chat/send", {
            method: "POST",
            credentials: "same-origin",
            headers: { "content-type": "application/json" },
            body: JSON.stringify(body),
          });
        } else {
          const controller = new AbortController();
          timeout = window.setTimeout(() => controller.abort(), IMAGE_TIMEOUT_MS);
          const form = new FormData();
          form.append("file", out.file);
          form.append("clientMsgId", clientMsgId);
          res = await fetch("/api/chat/send-image", {
            method: "POST",
            credentials: "same-origin",
            body: form,
            signal: controller.signal,
          });
        }
        if (!res.ok) {
          const fallback = out.kind === "image" ? IMAGE_FAIL : TEXT_FAIL;
          if (res.status === 401) goGuest();
          if (res.status === 503) {
            // Chat dimatikan toko → langsung layar WhatsApp; simpanan setelan basi.
            forgetChatConfig();
            if (mountedRef.current) setStatus("disabled");
          }
          throw new Error(await readErrorText(res, fallback));
        }
        outgoingRef.current.delete(clientMsgId);
        if (mountedRef.current) setErrorText(null);
        markActive();
        void pollOnce();
        return true;
      } catch (e) {
        const detail = e instanceof Error && e.name !== "AbortError" ? e.message : "";
        if (mountedRef.current) {
          if (track) applyMessages((cur) => markFailed(cur, clientMsgId));
          setErrorText(detail || (out.kind === "image" ? IMAGE_FAIL : TEXT_FAIL));
        }
        return false;
      } finally {
        if (timeout !== undefined) window.clearTimeout(timeout);
      }
    },
    [applyMessages, pollOnce, goGuest, markActive],
  );

  const sendText = useCallback(
    async (raw: string) => {
      const text = raw.trim();
      if (!text) return;
      const clientMsgId = newClientMsgId();
      // Konteks hanya ikut di pesan pertama, lalu dilepas.
      const ctx = pendingContextRef.current ?? undefined;
      const out: Outgoing = { kind: "text", text, context: ctx };
      outgoingRef.current.set(clientMsgId, out);
      applyMessages((cur) => [...cur, pendingMessage({ clientMsgId, text, now: Date.now() })]);
      markActive();
      if (ctx) clearContext();
      await deliver(clientMsgId, out, true);
    },
    [applyMessages, clearContext, deliver, markActive],
  );

  const sendImage = useCallback(
    async (file: File) => {
      if (!IMAGE_TYPES.includes(file.type) || file.size > IMAGE_MAX_BYTES) {
        setErrorText(IMAGE_INVALID);
        return;
      }
      const clientMsgId = newClientMsgId();
      const imagePreviewUrl = URL.createObjectURL(file);
      previewUrlsRef.current.set(clientMsgId, imagePreviewUrl);
      const out: Outgoing = { kind: "image", file };
      outgoingRef.current.set(clientMsgId, out);
      applyMessages((cur) => [...cur, pendingMessage({ clientMsgId, imagePreviewUrl, now: Date.now() })]);
      markActive();
      await deliver(clientMsgId, out, true);
    },
    [applyMessages, deliver, markActive],
  );

  // Kirim ulang dengan clientMsgId yang SAMA (server idempoten).
  const retry = useCallback(
    async (clientMsgId: string) => {
      const out = outgoingRef.current.get(clientMsgId);
      if (!out) return;
      applyMessages((cur) =>
        cur.map((m) =>
          m.clientMsgId === clientMsgId && m.localState === "failed" ? { ...m, localState: "sending" } : m,
        ),
      );
      await deliver(clientMsgId, out, true);
    },
    [applyMessages, deliver],
  );

  // ── Konteks pesanan: kirim otomatis sekali per percakapan+konteks ────
  // autoSentRef hanya berlaku selama terpasang; maka dicek juga apakah kartu
  // pesanan yang sama SUDAH ada di percakapan (jendela dibuka ulang, kembali /
  // muat ulang /chat?order=…) — kalau sudah, tidak dikirim lagi.
  useEffect(() => {
    if (status !== "ready" || !chatId || pendingContext?.type !== "order") return;
    const key = `${chatId}|${pendingContext.orderNumber}`;
    if (autoSentRef.current === key) return;
    autoSentRef.current = key;
    const ctx = pendingContext;
    setContext(null);
    const alreadySent = messagesRef.current.some(
      (m) => m.type === "order_context" && m.order?.orderNumber === ctx.orderNumber,
    );
    if (alreadySent) {
      notifyConsumed();
      return;
    }
    void deliver(newClientMsgId(), { kind: "text", context: ctx }, false).then((ok) => {
      if (ok) notifyConsumed();
      // Gagal: kartu pesanan ikut di pesan berikutnya yang diketik.
      else if (mountedRef.current && pendingContextRef.current === null) setContext(ctx);
    });
  }, [status, chatId, pendingContext, deliver, setContext, notifyConsumed]);

  return {
    status,
    messages,
    online,
    hasOlder,
    loadingOlder,
    loadOlder,
    sendText,
    sendImage,
    retry,
    pendingContext,
    clearContext,
    errorText,
    announcement,
  };
}
