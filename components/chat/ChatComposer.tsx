"use client";

import { useEffect, useRef, useState } from "react";
import { IoCameraOutline, IoClose, IoSend } from "react-icons/io5";
import type { ChatContext } from "@/lib/chat/web-client";

const MAX_LEN = 4000;

export function ChatComposer({
  onSendText,
  onSendImage,
  errorText,
  pendingContext,
  contextLabel,
  onClearContext,
}: {
  onSendText: (text: string) => void | Promise<void>;
  onSendImage: (file: File) => void | Promise<void>;
  errorText: string | null;
  pendingContext: ChatContext | null;
  /** Nama yang ditampilkan di bilah konteks, mis. nama produk. */
  contextLabel?: string;
  onClearContext: () => void;
}) {
  const [text, setText] = useState("");
  const [dismissedError, setDismissedError] = useState<string | null>(null);
  const areaRef = useRef<HTMLTextAreaElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const el = areaRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 104)}px`;
  }, [text]);

  useEffect(() => () => document.body.classList.remove("nat-keyboard-open"), []);

  const canSend = text.trim().length > 0;

  function submit() {
    const value = text.trim();
    if (!value) return;
    setText("");
    setDismissedError(null);
    void onSendText(value);
  }

  function isTouch(): boolean {
    return typeof window !== "undefined" && window.matchMedia("(pointer: coarse)").matches;
  }

  const shownError = errorText && errorText !== dismissedError ? errorText : null;

  const ctxText =
    contextLabel ??
    (pendingContext?.type === "order" ? `Pesanan ${pendingContext.orderNumber}` : "");

  return (
    <div className="border-t border-slate-200 bg-white pb-[env(safe-area-inset-bottom)]">
      {pendingContext && (
        <div className="flex items-center gap-2 border-b border-slate-100 bg-natalo-50 pl-3">
          <div className="min-w-0 flex-1 py-1.5 text-[12.5px]">
            <span className="font-bold text-natalo-700">
              {pendingContext.type === "order" ? "Menanyakan pesanan" : "Menanyakan produk"}
            </span>
            {ctxText && <span className="ml-1 truncate text-slate-600">{ctxText}</span>}
          </div>
          <button
            type="button"
            aria-label="Hapus konteks"
            onClick={onClearContext}
            className="flex h-11 w-11 flex-none items-center justify-center text-slate-500"
          >
            <IoClose className="h-5 w-5" />
          </button>
        </div>
      )}
      {shownError && (
        <p role="alert" className="px-3 pt-2 text-[12.5px] font-semibold text-red-600">
          {shownError}
        </p>
      )}
      <div className="flex items-end gap-1.5 p-2">
        <button
          type="button"
          aria-label="Kirim foto"
          onClick={() => fileRef.current?.click()}
          className="flex h-11 w-11 flex-none items-center justify-center rounded-full text-slate-600"
        >
          <IoCameraOutline className="h-6 w-6" />
        </button>
        <input
          ref={fileRef}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0];
            e.target.value = "";
            setDismissedError(null);
            if (f) void onSendImage(f);
          }}
        />
        <textarea
          ref={areaRef}
          rows={1}
          value={text}
          maxLength={MAX_LEN}
          placeholder="Tulis pesan…"
          aria-label="Tulis pesan"
          onChange={(e) => {
            setText(e.target.value);
            if (errorText) setDismissedError(errorText);
          }}
          onFocus={() => document.body.classList.add("nat-keyboard-open")}
          onBlur={() => document.body.classList.remove("nat-keyboard-open")}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing && !isTouch()) {
              e.preventDefault();
              submit();
            }
          }}
          className="max-h-[104px] min-h-[44px] flex-1 resize-none rounded-3xl bg-[#f8fafc] px-4 py-[11px] text-[15px] leading-snug text-slate-800 outline-none placeholder:text-slate-400 focus-visible:ring-2 focus-visible:ring-natalo-400"
        />
        <button
          type="button"
          aria-label="Kirim"
          disabled={!canSend}
          onClick={submit}
          className="flex h-11 w-11 flex-none items-center justify-center rounded-full bg-natalo-500 text-white disabled:opacity-40"
        >
          <IoSend className="h-5 w-5" />
        </button>
      </div>
    </div>
  );
}
