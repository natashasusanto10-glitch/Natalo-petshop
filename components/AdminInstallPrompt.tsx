"use client";

import { useEffect, useState } from "react";

type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
};

function isStandalone() {
  return (
    window.matchMedia?.("(display-mode: standalone)").matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

export function AdminInstallPrompt() {
  const [installEvent, setInstallEvent] = useState<BeforeInstallPromptEvent | null>(null);
  const [installed, setInstalled] = useState(false);

  useEffect(() => {
    setInstalled(isStandalone());

    function handleBeforeInstallPrompt(event: Event) {
      event.preventDefault();
      setInstallEvent(event as BeforeInstallPromptEvent);
    }

    function handleInstalled() {
      setInstalled(true);
      setInstallEvent(null);
    }

    window.addEventListener("beforeinstallprompt", handleBeforeInstallPrompt);
    window.addEventListener("appinstalled", handleInstalled);

    return () => {
      window.removeEventListener("beforeinstallprompt", handleBeforeInstallPrompt);
      window.removeEventListener("appinstalled", handleInstalled);
    };
  }, []);

  async function install() {
    if (!installEvent) return;
    await installEvent.prompt();
    await installEvent.userChoice.catch(() => null);
    setInstallEvent(null);
  }

  if (installed) {
    return (
      <div className="rounded-2xl border border-green-100 bg-green-50 px-4 py-3 text-sm font-bold text-green-700">
        Admin PWA aktif
      </div>
    );
  }

  return (
    <div className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <p className="text-sm font-black text-zinc-950">Pasang Admin di perangkat</p>
      <p className="mt-1 text-xs leading-5 text-zinc-500">
        Buka dashboard seperti aplikasi, langsung masuk ke admin, lebih cepat untuk edit produk dan order.
      </p>
      {installEvent ? (
        <button
          type="button"
          onClick={install}
          className="mt-3 rounded-full bg-zinc-950 px-4 py-2 text-xs font-black text-white transition hover:bg-zinc-800"
        >
          Install Admin PWA
        </button>
      ) : (
        <p className="mt-3 rounded-xl bg-zinc-50 px-3 py-2 text-xs font-semibold text-zinc-500">
          Jika tombol install belum muncul, buka menu browser lalu pilih Install app/Add to Home Screen.
        </p>
      )}
    </div>
  );
}
