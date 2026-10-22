"use client";

import { Fragment, useCallback, useLayoutEffect, useRef, useState } from "react";
import { IoArrowBack, IoClose, IoRemove } from "react-icons/io5";
import { chatHrefWithName, type ChatContext } from "@/lib/chat/web-client";
import { ChatComposer } from "./ChatComposer";
import { ChatIcon } from "./ChatIcon";
import { ChatMessageItem } from "./ChatMessageItem";
import { useCustomerChat } from "./useCustomerChat";
import { chatWhatsAppHref } from "./whatsapp";

type Props = {
  variant: "page" | "window";
  context: ChatContext | null;
  onBack?: () => void;
  onMinimize?: () => void;
  onClose?: () => void;
  /** Nama konteks (mis. nama produk) untuk bilah di atas kotak tulis; hanya tampilan. */
  contextLabel?: string;
  /** Konteks sudah terkirim / dibatalkan → pemanggil boleh membuangnya (tanpa pasang ulang). */
  onContextConsumed?: () => void;
};

const dayFmt = new Intl.DateTimeFormat("id-ID", {
  timeZone: "Asia/Jakarta",
  day: "numeric",
  month: "long",
  year: "numeric",
});
const dayKeyFmt = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta" });

function dayKey(ms: number): string {
  return dayKeyFmt.format(new Date(ms));
}

function dayLabel(ms: number): string {
  const key = dayKey(ms);
  const now = Date.now();
  if (key === dayKey(now)) return "Hari ini";
  if (key === dayKey(now - 86_400_000)) return "Kemarin";
  return dayFmt.format(new Date(ms));
}

// Tujuan kembali setelah masuk/daftar: SELALU halaman /chat dengan konteks yang
// sama (bukan halaman tempat jendela kecil dibuka), supaya pertanyaan soal
// pesanan/produk tidak hilang. Murni dari props — tidak membaca window, jadi
// aman dihitung saat render (hasil server & peramban sama).
function authHref(base: "/member/login" | "/member/register", context: ChatContext | null, label?: string): string {
  const ctx =
    context?.type === "order"
      ? { orderNumber: context.orderNumber }
      : context?.type === "product"
        ? { productId: context.productId }
        : undefined;
  return `${base}?redirect=${encodeURIComponent(chatHrefWithName(ctx, label))}`;
}

const btnPrimary =
  "inline-flex min-h-[44px] w-full items-center justify-center rounded-full bg-natalo-500 px-5 text-[15px] font-extrabold text-white";
const btnSecondary =
  "inline-flex min-h-[44px] w-full items-center justify-center rounded-full border border-slate-200 bg-white px-5 text-[15px] font-extrabold text-natalo-500";

export function ChatConversation(props: Props) {
  // Kunci ganti = pasang ulang percakapan (untuk tombol "Coba lagi").
  const [attempt, setAttempt] = useState(0);
  return <ConversationInner key={attempt} {...props} onReload={() => setAttempt((n) => n + 1)} />;
}

function ConversationInner({
  variant,
  context,
  onBack,
  onMinimize,
  onClose,
  contextLabel,
  onContextConsumed,
  onReload,
}: Props & { onReload: () => void }) {
  const isWindow = variant === "window";
  const chat = useCustomerChat({ enabled: true, context, onContextConsumed });
  const { status, messages, online } = chat;

  const listRef = useRef<HTMLDivElement>(null);
  const atBottomRef = useRef(true);
  const firstScrollRef = useRef(true);
  const lastCountRef = useRef(0);
  const forceBottomRef = useRef(false);
  const olderRef = useRef<{ firstKey: string | null; height: number; top: number } | null>(null);

  const onScroll = useCallback(() => {
    const el = listRef.current;
    if (!el) return;
    atBottomRef.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
  }, []);

  useLayoutEffect(() => {
    const el = listRef.current;
    if (!el || status !== "ready") return;
    const grew = messages.length > lastCountRef.current;
    lastCountRef.current = messages.length;
    const snap = olderRef.current;
    const firstKey = messages.length > 0 ? messages[0].localKey : null;
    if (snap && firstKey !== snap.firstKey) {
      // Pesan lama ditambahkan di atas: pertahankan posisi baca.
      el.scrollTop = el.scrollHeight - snap.height + snap.top;
      olderRef.current = null;
    } else if (firstScrollRef.current && messages.length > 0) {
      el.scrollTop = el.scrollHeight;
      firstScrollRef.current = false;
    } else if (grew && (atBottomRef.current || forceBottomRef.current)) {
      el.scrollTop = el.scrollHeight;
    }
    if (grew) forceBottomRef.current = false;
  }, [messages, status]);

  // Tidak ada halaman lebih lama / gagal: buang catatan posisi tanpa memulihkan.
  const loadingOlder = chat.loadingOlder;
  useLayoutEffect(() => {
    if (!loadingOlder) olderRef.current = null;
  }, [loadingOlder]);

  const loadOlder = useCallback(async () => {
    const el = listRef.current;
    if (el) {
      olderRef.current = {
        firstKey: messages.length > 0 ? messages[0].localKey : null,
        height: el.scrollHeight,
        top: el.scrollTop,
      };
    }
    await chat.loadOlder();
  }, [chat, messages]);

  const sendText = useCallback(
    (t: string) => {
      forceBottomRef.current = true;
      return chat.sendText(t).finally(() => {
        forceBottomRef.current = false;
      });
    },
    [chat],
  );
  const sendImage = useCallback(
    (f: File) => {
      forceBottomRef.current = true;
      return chat.sendImage(f).finally(() => {
        forceBottomRef.current = false;
      });
    },
    [chat],
  );

  const onImageLoad = useCallback(() => {
    const el = listRef.current;
    if (el && atBottomRef.current) el.scrollTop = el.scrollHeight;
  }, []);

  const header = (
    <header
      className={`flex flex-none items-center gap-1 border-b border-[#e2e8f0] bg-white px-2 ${
        isWindow ? "h-[58px]" : "h-16"
      }`}
    >
      {!isWindow && (
        <button
          type="button"
          aria-label="Kembali"
          onClick={onBack}
          className="flex h-11 w-11 flex-none items-center justify-center rounded-full text-slate-700"
        >
          <IoArrowBack className="h-6 w-6" />
        </button>
      )}
      <div className={`min-w-0 flex-1 ${isWindow ? "pl-2" : ""}`}>
        <h2
          className={`truncate font-extrabold leading-tight text-slate-900 ${
            isWindow ? "text-[15.5px]" : "text-[17px]"
          }`}
        >
          Natalo Petshop &amp; Aquarium
        </h2>
        {status === "ready" && online !== null && (
          <p
            className={`flex items-center gap-1.5 text-[11px] font-extrabold ${
              online ? "text-[#15803d]" : "text-slate-500"
            }`}
          >
            <span
              aria-hidden="true"
              className={`h-2 w-2 rounded-full ${online ? "bg-[#22c55e]" : "bg-slate-400"}`}
            />
            {online ? "Online" : "Di luar jam operasional"}
          </p>
        )}
      </div>
      {isWindow && (
        <>
          <button
            type="button"
            aria-label="Kecilkan"
            onClick={onMinimize}
            className="flex h-11 w-11 flex-none items-center justify-center rounded-full text-slate-600"
          >
            <IoRemove className="h-6 w-6" />
          </button>
          <button
            type="button"
            aria-label="Tutup"
            onClick={onClose}
            className="flex h-11 w-11 flex-none items-center justify-center rounded-full text-slate-600"
          >
            <IoClose className="h-6 w-6" />
          </button>
        </>
      )}
    </header>
  );

  let body: React.ReactNode;

  if (status === "loading") {
    body = (
      <div className="flex flex-1 items-center justify-center bg-[#f8fafc]" role="status">
        <span className="text-[14px] font-semibold text-slate-500">Memuat percakapan…</span>
      </div>
    );
  } else if (status === "guest") {
    body = (
      <div className="flex flex-1 flex-col items-center justify-center gap-3 bg-[#f8fafc] px-6 text-center">
        <span className="flex h-20 w-20 items-center justify-center rounded-full bg-natalo-50 text-natalo-500">
          <ChatIcon className="h-10 w-10" />
        </span>
        <h3 className="text-[18px] font-extrabold text-slate-900">Masuk dulu untuk chat</h3>
        <p className="max-w-[300px] text-[14px] leading-relaxed text-slate-600">
          Supaya toko tahu pesanan dan riwayat belanjamu, chat hanya bisa dipakai setelah masuk akun.
        </p>
        <div className="mt-2 flex w-full max-w-[300px] flex-col gap-2">
          <a href={authHref("/member/login", context, contextLabel)} className={btnPrimary}>
            Masuk
          </a>
          <a href={authHref("/member/register", context, contextLabel)} className={btnSecondary}>
            Daftar akun baru
          </a>
        </div>
      </div>
    );
  } else if (status === "disabled") {
    body = (
      <div className="flex flex-1 flex-col bg-[#f8fafc]">
        <p className="border-b border-amber-200 bg-amber-50 px-4 py-3 text-[13.5px] font-semibold text-amber-900">
          Chat sedang tidak bisa dipakai. Hubungi kami lewat WhatsApp dulu ya.
        </p>
        <div className="flex flex-1 flex-col items-center justify-center gap-3 px-6 text-center">
          <span className="flex h-20 w-20 items-center justify-center rounded-full bg-natalo-50 text-natalo-500">
            <ChatIcon className="h-10 w-10" />
          </span>
          <a
            href={chatWhatsAppHref()}
            target="_blank"
            rel="noopener noreferrer"
            className={`${btnPrimary} max-w-[300px]`}
          >
            Chat lewat WhatsApp
          </a>
        </div>
      </div>
    );
  } else if (status === "error") {
    body = (
      <div className="flex flex-1 flex-col items-center justify-center gap-3 bg-[#f8fafc] px-6 text-center">
        <p role="alert" className="max-w-[300px] text-[14px] text-slate-700">
          {chat.errorText ?? "Chat belum bisa dimuat. Coba lagi sebentar lagi."}
        </p>
        <button type="button" onClick={onReload} className={`${btnPrimary} max-w-[220px]`}>
          Coba lagi
        </button>
      </div>
    );
  } else {
    let prevDay = "";
    body = (
      <>
        <div
          ref={listRef}
          onScroll={onScroll}
          className="flex-1 overflow-y-auto bg-[#f8fafc] p-3"
        >
          {chat.hasOlder && (
            <div className="mb-2 flex justify-center">
              <button
                type="button"
                disabled={chat.loadingOlder}
                onClick={() => void loadOlder()}
                className="min-h-[44px] rounded-full border border-slate-200 bg-white px-4 text-[13px] font-bold text-natalo-500 disabled:opacity-60"
              >
                {chat.loadingOlder ? "Memuat…" : "Muat pesan sebelumnya"}
              </button>
            </div>
          )}
          {messages.length === 0 ? (
            <div className="flex h-full flex-col items-center justify-center gap-1 px-6 text-center">
              <p className="text-[15px] font-extrabold text-slate-800">
                Mulai percakapan dengan Natalo Petshop
              </p>
              <p className="text-[13px] text-slate-600">
                Tim kami siap bantu pertanyaan produk &amp; pesananmu.
              </p>
            </div>
          ) : (
            messages.map((m) => {
              const key = m.createdAt > 0 ? dayKey(m.createdAt) : prevDay;
              const showDay = key !== prevDay && m.createdAt > 0;
              prevDay = key;
              return (
                <Fragment key={m.localKey}>
                  {showDay && (
                    <div className="my-2 flex justify-center">
                      <span className="rounded-full bg-slate-200/70 px-3 py-1 text-[11.5px] font-bold text-slate-600">
                        {dayLabel(m.createdAt)}
                      </span>
                    </div>
                  )}
                  <ChatMessageItem
                    message={m}
                    onRetry={(id) => void chat.retry(id)}
                    onImageLoad={onImageLoad}
                  />
                </Fragment>
              );
            })
          )}
        </div>
        <ChatComposer
          onSendText={sendText}
          onSendImage={sendImage}
          errorText={chat.errorText}
          pendingContext={chat.pendingContext}
          contextLabel={contextLabel}
          onClearContext={chat.clearContext}
        />
      </>
    );
  }

  return (
    <section
      aria-label="Percakapan dengan Natalo Petshop"
      className={`flex h-full min-h-0 flex-col overflow-hidden bg-white ${
        isWindow ? "rounded-2xl border border-slate-200 shadow-xl" : ""
      }`}
    >
      {header}
      {body}
      {/* Hanya pesan toko yang baru masuk yang diumumkan (bukan seluruh daftar). */}
      <div aria-live="polite" aria-atomic="true" className="sr-only">
        {status === "ready" && chat.announcement && (
          <span key={chat.announcement.id}>{chat.announcement.text}</span>
        )}
      </div>
    </section>
  );
}
