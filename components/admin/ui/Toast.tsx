"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";

/**
 * Sistem toast admin — feedback seragam (ganti pesan inline tersebar).
 * Pasang <ToastProvider> sekali di layout admin; komponen klien mana pun di
 * bawahnya panggil `useAdminToast().show("Tersimpan")`.
 */
type ToastTone = "success" | "error" | "info";
type ToastItem = { id: number; message: string; tone: ToastTone };

type ToastCtx = { show: (message: string, tone?: ToastTone) => void };

const Ctx = createContext<ToastCtx | null>(null);

export function useAdminToast(): ToastCtx {
  const ctx = useContext(Ctx);
  if (!ctx)
    throw new Error("useAdminToast harus dipakai di dalam <ToastProvider>");
  return ctx;
}

let _toastId = 0;

const TONE_ICON: Record<ToastTone, string> = {
  success: "M20 6 9 17l-5-5",
  error: "M18 6 6 18M6 6l12 12",
  info: "M12 16v-4M12 8h.01",
};
const TONE_COLOR: Record<ToastTone, string> = {
  success: "text-emerald-600",
  error: "text-red-600",
  info: "text-sky-600",
};

export function ToastProvider({ children }: { children: ReactNode }) {
  const timers = useRef(new Map<number, ReturnType<typeof setTimeout>>());
  useEffect(() => {
    const activeTimers = timers.current;
    return () => {
      activeTimers.forEach(clearTimeout);
      activeTimers.clear();
    };
  }, []);
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  const dismiss = useCallback((id: number) => {
    const timer = timers.current.get(id);
    if (timer !== undefined) clearTimeout(timer);
    timers.current.delete(id);
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const show = useCallback<ToastCtx["show"]>((message, tone = "success") => {
    const id = (_toastId += 1);
    setToasts((prev) => [...prev, { id, message, tone }]);
    timers.current.set(
      id,
      setTimeout(() => {
        timers.current.delete(id);
        setToasts((prev) => prev.filter((t) => t.id !== id));
      }, 6000)
    );
  }, []);

  return (
    <Ctx.Provider value={{ show }}>
      {children}
      <div
        className="sr-only"
        role="status"
        aria-live="polite"
        aria-atomic="true"
      >
        {toasts.at(-1)?.message}
      </div>
      {toasts.length > 0 && (
        <div className="pointer-events-none fixed inset-x-0 top-4 z-[80] flex flex-col items-center gap-2 px-4">
          {toasts.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => dismiss(t.id)}
              aria-label={`Tutup notifikasi: ${t.message}`}
              className="admin-toast pointer-events-auto flex min-h-11 max-w-md items-center gap-2 rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm font-semibold text-slate-800 shadow-lg"
            >
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2.5}
                strokeLinecap="round"
                strokeLinejoin="round"
                className={`h-4 w-4 shrink-0 ${TONE_COLOR[t.tone]}`}
                aria-hidden="true"
              >
                {t.tone === "info" ? (
                  <>
                    <circle cx="12" cy="12" r="9" />
                    <path d={TONE_ICON.info} />
                  </>
                ) : (
                  <path d={TONE_ICON[t.tone]} />
                )}
              </svg>
              <span>{t.message}</span>
            </button>
          ))}
        </div>
      )}
    </Ctx.Provider>
  );
}
