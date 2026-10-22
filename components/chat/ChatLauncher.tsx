"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { chatHref, type ChatContext } from "@/lib/chat/web-client";
import { ChatConversation } from "./ChatConversation";

export type OpenChatDetail = { orderNumber?: string; productId?: string; productName?: string };

const EVENT = "open-chat";
const DESKTOP_QUERY = "(min-width: 768px)";
const HIDDEN_ROUTES = [/^\/chat(\/|$)/, /^\/admin(\/|$)/, /^\/checkout(\/|$)/, /^\/member\/login(\/|$)/];

export function openChat(ctx?: OpenChatDetail): void {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent<OpenChatDetail>(EVENT, { detail: ctx ?? {} }));
}

function toContext(d: OpenChatDetail): ChatContext | null {
  if (d.orderNumber) return { type: "order", orderNumber: d.orderNumber };
  if (d.productId) return { type: "product", productId: d.productId };
  return null;
}

type WindowState = { ctx: ChatContext | null; label?: string; minimized: boolean };

export function ChatLauncher() {
  const router = useRouter();
  const pathname = usePathname();
  const pathRef = useRef(pathname);
  pathRef.current = pathname;
  const [state, setState] = useState<WindowState | null>(null);
  const openerRef = useRef<HTMLElement | null>(null);
  const dialogRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    function onOpen(e: Event) {
      const detail = ((e as CustomEvent<OpenChatDetail>).detail ?? {}) as OpenChatDetail;
      const onChatRoute = /^\/chat(\/|$)/.test(pathRef.current ?? "");
      const desktop = window.matchMedia(DESKTOP_QUERY).matches;
      if (!desktop || onChatRoute) {
        let href = chatHref(detail);
        const name = detail.productName?.trim().slice(0, 80);
        if (name && href.includes("?")) href += `&pname=${encodeURIComponent(name)}`;
        router.push(href);
        return;
      }
      const active = document.activeElement;
      openerRef.current = active instanceof HTMLElement && active !== document.body ? active : null;
      setState({ ctx: toContext(detail), label: detail.productName?.trim().slice(0, 80) || undefined, minimized: false });
    }
    window.addEventListener(EVENT, onOpen);
    return () => window.removeEventListener(EVENT, onOpen);
  }, [router]);

  const restoreFocus = useCallback(() => {
    const el = openerRef.current;
    openerRef.current = null;
    if (el && el.isConnected) el.focus();
  }, []);

  const close = useCallback(() => {
    setState(null);
    restoreFocus();
  }, [restoreFocus]);

  const minimize = useCallback(() => {
    setState((s) => (s ? { ...s, minimized: true } : s));
    restoreFocus();
  }, [restoreFocus]);

  const hidden = HIDDEN_ROUTES.some((re) => re.test(pathname ?? ""));
  const visible = Boolean(state && !state.minimized && !hidden);
  const ctxKey = state?.ctx ? JSON.stringify(state.ctx) : "none";

  // Fokus ke kolom tulis (muncul setelah percakapan selesai dimuat); tamu: ke jendela.
  useEffect(() => {
    if (!visible) return;
    let tries = 0;
    const timer = window.setInterval(() => {
      const box = dialogRef.current;
      if (!box) return;
      const area = box.querySelector("textarea");
      tries += 1;
      if (area) {
        area.focus();
        window.clearInterval(timer);
      } else if (tries >= 20) {
        box.focus();
        window.clearInterval(timer);
      }
    }, 100);
    return () => window.clearInterval(timer);
  }, [visible, ctxKey]);

  useEffect(() => {
    if (!visible) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") close();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [visible, close]);

  if (!visible || !state) return null;

  return (
    <div
      ref={dialogRef}
      role="dialog"
      aria-label="Chat dengan Natalo Petshop"
      tabIndex={-1}
      className="fixed bottom-6 right-6 z-[90] h-[min(560px,calc(100vh-120px))] w-[370px] overflow-hidden rounded-[18px] border border-slate-200 bg-white shadow-[0_18px_50px_rgba(15,40,70,.28)] outline-none"
    >
      <ChatConversation
        key={ctxKey}
        variant="window"
        context={state.ctx}
        contextLabel={state.label}
        onMinimize={minimize}
        onClose={close}
      />
    </div>
  );
}
