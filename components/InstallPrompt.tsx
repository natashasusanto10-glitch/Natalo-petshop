"use client";

import { useEffect, useState } from "react";

type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

const DISMISS_KEY = "pwa-install-dismissed";

export function InstallPrompt() {
  const [evt, setEvt] = useState<BeforeInstallPromptEvent | null>(null);

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (localStorage.getItem(DISMISS_KEY)) return;

    function onPrompt(e: Event) {
      e.preventDefault();
      setEvt(e as BeforeInstallPromptEvent);
    }
    window.addEventListener("beforeinstallprompt", onPrompt);
    return () => window.removeEventListener("beforeinstallprompt", onPrompt);
  }, []);

  if (!evt) return null;

  async function handleInstall() {
    if (!evt) return;
    await evt.prompt();
    await evt.userChoice;
    setEvt(null);
  }

  function handleDismiss() {
    localStorage.setItem(DISMISS_KEY, "1");
    setEvt(null);
  }

  return (
    <div className="fixed inset-x-4 bottom-4 z-50 mx-auto max-w-sm rounded-2xl border border-blue-200 bg-white p-4 shadow-lg">
      <p className="font-semibold text-zinc-900">Pasang aplikasi</p>
      <p className="mt-1 text-sm text-zinc-500">
        Tambahkan ke layar utama untuk akses cepat & notifikasi pesanan.
      </p>
      <div className="mt-3 flex gap-2">
        <button
          onClick={handleInstall}
          className="flex-1 rounded-full bg-blue-500 px-4 py-2 text-sm font-bold text-white hover:bg-blue-600"
        >
          Pasang
        </button>
        <button
          onClick={handleDismiss}
          className="rounded-full border border-zinc-200 px-4 py-2 text-sm font-semibold text-zinc-600 hover:bg-zinc-50"
        >
          Nanti
        </button>
      </div>
    </div>
  );
}
