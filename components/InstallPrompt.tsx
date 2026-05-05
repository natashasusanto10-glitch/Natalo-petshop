"use client";

import { useEffect, useState } from "react";

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

export function InstallPrompt() {
  const [prompt, setPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    // Jangan tampilkan kalau sudah pernah dismiss
    if (localStorage.getItem("pwa-dismissed")) {
      setDismissed(true);
      return;
    }

    const handler = (e: Event) => {
      e.preventDefault();
      setPrompt(e as BeforeInstallPromptEvent);
    };

    window.addEventListener("beforeinstallprompt", handler);
    return () => window.removeEventListener("beforeinstallprompt", handler);
  }, []);

  async function handleInstall() {
    if (!prompt) return;
    await prompt.prompt();
    const { outcome } = await prompt.userChoice;
    if (outcome === "accepted") setPrompt(null);
  }

  function handleDismiss() {
    localStorage.setItem("pwa-dismissed", "1");
    setPrompt(null);
    setDismissed(true);
  }

  if (!prompt || dismissed) return null;

  return (
    <div className="fixed bottom-4 left-4 right-4 z-50 flex items-center justify-between gap-4 rounded-2xl bg-gray-900 px-5 py-4 text-white shadow-xl md:left-auto md:right-6 md:max-w-sm">
      <div className="flex items-center gap-3">
        <span className="text-2xl">🐾</span>
        <div>
          <p className="text-sm font-bold">Install Aplikasi</p>
          <p className="text-xs text-gray-400">Akses lebih cepat dari layar utama HP</p>
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        <button
          onClick={handleDismiss}
          className="rounded-full px-3 py-1.5 text-xs text-gray-400 transition hover:text-white"
        >
          Nanti
        </button>
        <button
          onClick={handleInstall}
          className="rounded-full bg-orange-500 px-4 py-1.5 text-xs font-bold text-white transition hover:bg-orange-600"
        >
          Install
        </button>
      </div>
    </div>
  );
}
