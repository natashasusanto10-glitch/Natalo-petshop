"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { orderCardLabel, type WebChatMessage } from "@/lib/chat/web-client";

const URL_RE = /(https?:\/\/[^\s<>]+)/g;
const TRAILING = /[.,;:!?)\]]+$/;

function linkify(text: string, linkClass: string): ReactNode[] {
  return text.split(URL_RE).map((part, i) => {
    if (i % 2 === 0) return part;
    const trail = part.match(TRAILING)?.[0] ?? "";
    const url = trail ? part.slice(0, -trail.length) : part;
    return (
      <span key={i}>
        <a href={url} target="_blank" rel="noopener noreferrer" className={linkClass}>
          {url}
        </a>
        {trail}
      </span>
    );
  });
}

const rupiah = (n: number) => `Rp ${new Intl.NumberFormat("id-ID").format(n)}`;
const timeFmt = new Intl.DateTimeFormat("id-ID", {
  timeZone: "Asia/Jakarta",
  hour: "2-digit",
  minute: "2-digit",
  hour12: false,
});
const clock = (ms: number) => (ms > 0 ? timeFmt.format(new Date(ms)).replace(".", ":") : "");

const TONE: Record<"ok" | "warn" | "bad" | "info", string> = {
  ok: "bg-green-100 text-green-700",
  warn: "bg-amber-100 text-amber-800",
  bad: "bg-red-100 text-red-700",
  info: "bg-natalo-50 text-natalo-700",
};

export function ChatMessageItem({
  message,
  onRetry,
  onImageLoad,
}: {
  message: WebChatMessage;
  onRetry?: (clientMsgId: string) => void;
  onImageLoad?: () => void;
}) {
  const m = message;

  if (m.type === "system" || m.auto) {
    return (
      <div className="my-2 flex justify-center">
        <p className="max-w-[88%] whitespace-pre-wrap break-words rounded-xl border border-dashed border-[#cbd5e1] bg-white px-3 py-1.5 text-center text-[12.5px] text-slate-600">
          {m.text}
        </p>
      </div>
    );
  }

  const mine = m.senderRole === "customer";
  const time = clock(m.createdAt);

  const meta = (
    <div className={`mt-1 flex items-center gap-2 text-[10px] ${mine ? "justify-end text-white/80" : "text-slate-500"}`}>
      {m.localState === "sending" ? <span>Mengirim…</span> : time ? <span>{time}</span> : null}
    </div>
  );

  const failed =
    m.localState === "failed" ? (
      <button
        type="button"
        onClick={() => m.clientMsgId && onRetry?.(m.clientMsgId)}
        className="mt-1 inline-flex min-h-[44px] items-center text-[12px] font-bold text-red-600"
      >
        Belum terkirim · Coba lagi
      </button>
    ) : null;

  // Kartu pesanan (dari pembeli)
  if (m.type === "order_context" && m.order) {
    const label = orderCardLabel(m.order);
    return (
      <div className="mb-2 flex justify-end">
        <div className="w-[82%] max-w-[340px] rounded-2xl border border-slate-200 bg-white p-3 text-slate-800">
          <p className="text-[11px] font-extrabold uppercase tracking-wide text-slate-500">Pesanan</p>
          <p className="mt-0.5 break-words text-[14px] font-extrabold">
            {m.order.orderNumber}
            {typeof m.order.total === "number" ? ` · ${rupiah(m.order.total)}` : ""}
          </p>
          {typeof m.order.itemCount === "number" && (
            <p className="text-[12px] text-slate-600">{m.order.itemCount} barang</p>
          )}
          <span className={`mt-2 inline-block rounded-full px-2.5 py-1 text-[11px] font-bold ${TONE[label.tone]}`}>
            {label.text}
          </span>
          <Link
            href={`/pesanan/${encodeURIComponent(m.order.orderNumber)}`}
            className="mt-1 flex min-h-[44px] items-center text-[13px] font-bold text-natalo-500"
          >
            Lihat pesanan
          </Link>
          {time && <p className="text-right text-[10px] text-slate-500">{time}</p>}
        </div>
      </div>
    );
  }

  // Kartu produk
  if ((m.type === "product" || m.type === "product_context") && m.product) {
    const p = m.product;
    const body = (
      <div className="flex items-center gap-3">
        {p.imageUrl && /^(https:|blob:)/i.test(p.imageUrl) ? (
          <img src={p.imageUrl} alt="" loading="lazy" className="h-12 w-12 flex-none rounded-lg bg-slate-100 object-cover" />
        ) : (
          <div className="h-12 w-12 flex-none rounded-lg bg-slate-100" />
        )}
        <div className="min-w-0">
          <p className="line-clamp-2 text-[13px] font-bold text-slate-800">{p.name}</p>
          {typeof p.price === "number" && (
            <p className="text-[13px] font-extrabold text-natalo-500">{rupiah(p.price)}</p>
          )}
        </div>
      </div>
    );
    const cls = "block min-h-[44px] w-[82%] max-w-[340px] rounded-2xl border border-slate-200 bg-white p-2.5";
    return (
      <div className={`mb-2 flex ${mine ? "justify-end" : "justify-start"}`}>
        {p.slug ? (
          <Link href={`/products/${encodeURIComponent(p.slug)}`} className={cls}>
            {body}
          </Link>
        ) : (
          <div className={cls}>{body}</div>
        )}
      </div>
    );
  }

  const rawSrc = m.imagePreviewUrl ?? m.image?.url;
  const imgSrc = rawSrc && /^(https:|blob:)/i.test(rawSrc) ? rawSrc : undefined;
  const bubble = mine
    ? "bg-natalo-500 text-white rounded-xl rounded-tr-[4px]"
    : "bg-white border border-slate-200 text-slate-800 rounded-xl rounded-tl-[4px]";
  const linkClass = mine ? "underline break-all text-white" : "underline break-all text-natalo-500";

  return (
    <div className={`mb-2 flex ${mine ? "justify-end" : "justify-start"}`}>
      <div className="max-w-[78%]">
        <div className={`px-3 py-2 ${bubble}`}>
          {!mine && m.senderName && (
            <p className="mb-0.5 text-[11.5px] font-extrabold text-natalo-500">{m.senderName}</p>
          )}
          {m.replyTo && (
            <div
              className={`mb-1.5 rounded-md border-l-[3px] px-2 py-1 text-[12px] ${
                mine ? "border-white/70 bg-white/15" : "border-natalo-400 bg-slate-50"
              }`}
            >
              {m.replyTo.senderName && <p className="font-bold">{m.replyTo.senderName}</p>}
              <p className="line-clamp-2 break-words opacity-90">{m.replyTo.text || "Foto"}</p>
            </div>
          )}
          {m.type === "image" && !imgSrc && (
            <p className="text-[12.5px] opacity-80">Foto tidak bisa ditampilkan</p>
          )}
          {m.type === "image" && imgSrc && (
            <a href={imgSrc} target="_blank" rel="noopener noreferrer" className="block">
              <img
                src={imgSrc}
                alt="Foto dalam percakapan"
                loading="lazy"
                onLoad={onImageLoad}
                className="max-h-72 w-full max-w-[240px] rounded-xl object-cover"
              />
            </a>
          )}
          {m.text && (
            <p className="whitespace-pre-wrap break-words text-[14.5px] leading-snug">
              {linkify(m.text, linkClass)}
            </p>
          )}
          {meta}
        </div>
        {failed}
      </div>
    </div>
  );
}
