"use client";

import { useEffect, useRef, useState } from "react";

type ToastKind = "default" | "ok" | "warn" | "err";

type ToastAction = {
  label: string;
  onClick?: () => void;
};

type Toast = {
  id: number;
  msg: string;
  kind: ToastKind;
  actions?: ToastAction[];
};

type ToastEventDetail = {
  msg: string;
  kind?: ToastKind;
  action?: ToastAction;
  actions?: ToastAction[];
};

const EVENT = "nat-toast";
const DURATION_MS = 5000;

export function natToast(
  msg: string,
  opts?: { kind?: ToastKind; action?: ToastAction; actions?: ToastAction[] }
) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(
    new CustomEvent<ToastEventDetail>(EVENT, {
      detail: { msg, kind: opts?.kind, action: opts?.action, actions: opts?.actions },
    })
  );
}

export function ToastProvider() {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const timersRef = useRef<Map<number, ReturnType<typeof setTimeout>>>(new Map());

  useEffect(() => {
    function dismiss(id: number) {
      setToasts((prev) => prev.filter((t) => t.id !== id));
      const timer = timersRef.current.get(id);
      if (timer) {
        clearTimeout(timer);
        timersRef.current.delete(id);
      }
    }

    function handle(e: Event) {
      const detail = (e as CustomEvent<ToastEventDetail>).detail;
      if (!detail?.msg) return;
      const id = Date.now() + Math.random();
      const next: Toast = {
        id,
        msg: detail.msg,
        kind: detail.kind || "default",
        actions: detail.actions ?? (detail.action ? [detail.action] : undefined),
      };
      setToasts((prev) => [...prev, next].slice(-3));
      const timer = setTimeout(() => dismiss(id), DURATION_MS);
      timersRef.current.set(id, timer);
    }

    window.addEventListener(EVENT, handle);
    const timers = timersRef.current;
    return () => {
      window.removeEventListener(EVENT, handle);
      timers.forEach((t) => clearTimeout(t));
      timers.clear();
    };
  }, []);

  if (toasts.length === 0) return null;

  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-[88px] z-[70] flex flex-col items-center gap-2 px-4 md:bottom-6">
      {toasts.map((t) => (
        <ToastItem
          key={t.id}
          toast={t}
          onDismiss={() => setToasts((prev) => prev.filter((x) => x.id !== t.id))}
        />
      ))}
    </div>
  );
}

function ToastItem({ toast, onDismiss }: { toast: Toast; onDismiss: () => void }) {
  const colorMap: Record<ToastKind, string> = {
    default: "bg-zinc-900 text-white",
    ok: "bg-emerald-600 text-white",
    warn: "bg-amber-500 text-white",
    err: "bg-red-500 text-white",
  };

  const iconMap: Record<ToastKind, string> = {
    default: "Info",
    ok: "OK",
    warn: "!",
    err: "!",
  };

  return (
    <div
      role="status"
      className={`pointer-events-auto flex w-full max-w-md flex-wrap items-center gap-2.5 rounded-xl px-3.5 py-3 text-sm shadow-lg nat-toast-slide ${colorMap[toast.kind]}`}
    >
      <span aria-hidden className="text-[10px] font-black uppercase leading-none opacity-80">
        {iconMap[toast.kind]}
      </span>
      <span className="min-w-0 flex-1 leading-snug">{toast.msg}</span>
      {toast.actions && toast.actions.length > 0 && (
        <div className="flex shrink-0 items-center gap-1.5">
          {toast.actions.map((action) => (
            <button
              key={action.label}
              type="button"
              onClick={() => {
                action.onClick?.();
                onDismiss();
              }}
              className="rounded-md bg-white/20 px-2.5 py-1 text-xs font-bold hover:bg-white/30"
            >
              {action.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
