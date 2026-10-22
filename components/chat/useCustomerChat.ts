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

const POLL_MS = 4000;
const CONFIG_EVERY_ROUNDS = 5;
const IMAGE_TIMEOUT_MS = 90_000;
const IMAGE_MAX_BYTES = 5 * 1024 * 1024;
const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"];

const TEXT_FAIL = "Pesan belum terkirim. Coba lagi.";
const IMAGE_FAIL = "Foto belum terkirim. Coba lagi.";
const IMAGE_INVALID = "Foto harus JPG/PNG/WEBP, maksimal 5 MB.";
const LOAD_FAIL = "Chat belum bisa dibuka. Coba lagi sebentar lagi.";
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

async function readJson<T>(res: Response): Promise<T | null> {
  try {
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export function useCustomerChat(opts: { enabled: boolean; context: ChatContext | null }): {
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
} {
  const { enabled, context } = opts;

  const [status, setStatus] = useState<CustomerChatStatus>("loading");
  const [messages, setMessages] = useState<WebChatMessage[]>([]);
  const [online, setOnline] = useState<boolean | null>(null);
  const [hasOlder, setHasOlder] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [pendingContext, setPendingContext] = useState<ChatContext | null>(context);
  const [errorText, setErrorText] = useState<string | null>(null);
  const [chatId, setChatId] = useState<string | null>(null);

  const mountedRef = useRef(true);
  const messagesRef = useRef<WebChatMessage[]>([]);
  const cursorRef = useRef<number | null>(null);
  const prevCursorRef = useRef<number | null>(null);
  const pollBusyRef = useRef(false);
  const olderBusyRef = useRef(false);
  const roundRef = useRef(0);
  const pendingContextRef = useRef<ChatContext | null>(context);
  const outgoingRef = useRef(new Map<string, Outgoing>());
  const previewUrlsRef = useRef(new Map<string, string>());
  const autoSentRef = useRef<string | null>(null);
  const chatIdRef = useRef<string | null>(null);

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

  useEffect(() => {
    setContext(context);
  }, [context, setContext]);

  const clearContext = useCallback(() => setContext(null), [setContext]);

  // true = chat aktif, false = dimatikan, null = tidak tahu (gagal ambil).
  const checkConfig = useCallback(async (): Promise<boolean | null> => {
    try {
      const res = await fetch("/api/chat/config", { cache: "no-store", credentials: "same-origin" });
      if (!res.ok) return null;
      const json = await readJson<{ chatEnabled?: boolean; online?: boolean }>(res);
      if (!json || !mountedRef.current) return null;
      if (typeof json.online === "boolean") setOnline(json.online);
      return json.chatEnabled !== false;
    } catch {
      return null;
    }
  }, []);

  // ── Muat awal ────────────────────────────────────────────────────────
  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;
    setStatus("loading");
    setErrorText(null);

    (async () => {
      try {
        const [meRes, cfg] = await Promise.all([
          fetch("/api/auth/me", { cache: "no-store", credentials: "same-origin" }),
          checkConfig(),
        ]);
        if (cancelled) return;
        const me = meRes.ok ? await readJson<{ id?: string }>(meRes) : null;
        if (cancelled) return;
        if (!me?.id) {
          setStatus("guest");
          return;
        }
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
        const json = await readJson<PageJson>(res);
        if (cancelled) return;
        if (!res.ok || !json) {
          setErrorText(json?.error ?? LOAD_FAIL);
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
  const pollOnce = useCallback(async () => {
    const id = chatIdRef.current;
    if (!id || pollBusyRef.current) return;
    pollBusyRef.current = true;
    try {
      const after = cursorRef.current;
      const qs = after === null ? "" : `?after=${after}`;
      const res = await fetch(`/api/chat/${encodeURIComponent(id)}${qs}`, {
        cache: "no-store",
        credentials: "same-origin",
      });
      if (res.ok) {
        const json = await readJson<PageJson>(res);
        if (json && mountedRef.current) {
          applyMessages((cur) => mergeMessages(cur, json.messages ?? []));
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
    }
  }, [applyMessages, checkConfig]);

  useEffect(() => {
    if (status !== "ready") return;
    let stopped = false;
    let gen = 0;
    let timer: number | undefined;

    // Rantai setTimeout: satu putaran selesai dulu baru dijadwalkan berikutnya.
    const tick = async (myGen: number) => {
      if (document.visibilityState === "visible") await pollOnce();
      if (stopped || myGen !== gen) return;
      timer = window.setTimeout(() => void tick(myGen), POLL_MS);
    };
    const restart = () => {
      gen += 1;
      window.clearTimeout(timer);
      void tick(gen);
    };
    const onVisible = () => {
      if (document.visibilityState === "visible") restart();
    };

    timer = window.setTimeout(() => void tick(gen), POLL_MS);
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      stopped = true;
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [status, pollOnce]);

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
      const json = await readJson<PageJson>(res);
      if (!mountedRef.current) return;
      if (!res.ok || !json) {
        setErrorText(json?.error ?? OLDER_FAIL);
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
  }, [applyMessages]);

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
          const json = await readJson<{ error?: string }>(res);
          throw new Error(typeof json?.error === "string" ? json.error : "");
        }
        outgoingRef.current.delete(clientMsgId);
        if (mountedRef.current) setErrorText(null);
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
    [applyMessages, pollOnce],
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
      if (ctx) clearContext();
      await deliver(clientMsgId, out, true);
    },
    [applyMessages, clearContext, deliver],
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
      await deliver(clientMsgId, out, true);
    },
    [applyMessages, deliver],
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
  useEffect(() => {
    if (status !== "ready" || !chatId || pendingContext?.type !== "order") return;
    const key = `${chatId}|${pendingContext.orderNumber}`;
    if (autoSentRef.current === key) return;
    autoSentRef.current = key;
    const ctx = pendingContext;
    clearContext();
    void deliver(newClientMsgId(), { kind: "text", context: ctx }, false);
  }, [status, chatId, pendingContext, clearContext, deliver]);

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
  };
}
