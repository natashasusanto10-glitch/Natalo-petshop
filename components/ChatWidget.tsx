"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";

type Message = {
  id: string;
  senderRole: "ADMIN" | "CUSTOMER";
  content: string;
  createdAt: string;
};

export function ChatWidget() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [loggedIn, setLoggedIn] = useState<boolean | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  async function load() {
    try {
      const res = await fetch("/api/member/chat", { cache: "no-store" });
      if (res.status === 401) {
        setLoggedIn(false);
        return;
      }
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error || "Gagal memuat chat");
      setLoggedIn(true);
      setMessages(data.messages || []);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat chat");
    }
  }

  useEffect(() => {
    if (!open) return;
    load();
    const t = setInterval(load, 3000);
    return () => clearInterval(t);
  }, [open]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, open]);

  async function send() {
    const content = draft.trim();
    if (!content || sending) return;
    setSending(true);
    try {
      const res = await fetch("/api/member/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error || "Gagal mengirim pesan");
      setDraft("");
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal mengirim pesan");
    } finally {
      setSending(false);
    }
  }

  const hideOn = [
    "/admin",
    "/checkout",
    "/member/login",
    "/member/register",
    "/member/forgot-password",
    "/member/reset-password",
  ];
  const shouldHide = hideOn.some((path) => pathname === path || pathname.startsWith(`${path}/`));

  if (shouldHide) return null;

  return (
    <div className="fixed bottom-[150px] right-4 z-50 md:bottom-24">
      {open && (
        <div className="mb-3 flex h-[460px] w-[calc(100vw-2rem)] max-w-sm flex-col overflow-hidden rounded-2xl border border-zinc-200 bg-white shadow-xl">
          <div className="bg-[#E8711F] px-4 py-3 text-white">
            <p className="text-sm font-black">Chat Natalo Petshop</p>
            <p className="text-xs text-white/80">Admin akan membalas di sini</p>
          </div>

          {loggedIn === false ? (
            <div className="flex flex-1 flex-col items-center justify-center p-6 text-center">
              <p className="text-sm font-bold text-zinc-950">Masuk untuk chat dengan admin</p>
              <p className="mt-2 text-xs text-zinc-500">
                Chat tersimpan di akun member supaya admin bisa membalas pesanan Anda.
              </p>
              <Link
                href="/member/login"
                className="mt-4 rounded-full bg-zinc-950 px-5 py-2.5 text-sm font-bold text-white"
              >
                Masuk Member
              </Link>
            </div>
          ) : (
            <>
              <div className="flex-1 space-y-2 overflow-y-auto bg-zinc-50 p-3">
                {messages.length === 0 ? (
                  <p className="rounded-xl bg-white p-3 text-sm text-zinc-500">
                    Halo, ada yang bisa kami bantu?
                  </p>
                ) : (
                  messages.map((message) => {
                    const own = message.senderRole === "CUSTOMER";
                    return (
                      <div key={message.id} className={`flex ${own ? "justify-end" : "justify-start"}`}>
                        <div
                          className={`max-w-[80%] rounded-2xl px-3 py-2 text-sm ${
                            own ? "bg-[#E8711F] text-white" : "bg-white text-zinc-800"
                          }`}
                        >
                          {message.content}
                        </div>
                      </div>
                    );
                  })
                )}
                <div ref={bottomRef} />
              </div>

              {error && <p className="px-3 py-1 text-xs font-semibold text-red-600">{error}</p>}

              <div className="flex gap-2 border-t border-zinc-100 p-3">
                <input
                  value={draft}
                  onChange={(e) => setDraft(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") send();
                  }}
                  placeholder="Tulis pesan..."
                  className="min-w-0 flex-1 rounded-full border border-zinc-300 px-4 py-2 text-sm outline-none focus:border-[#E8711F]"
                />
                <button
                  type="button"
                  disabled={sending || !draft.trim()}
                  onClick={send}
                  className="rounded-full bg-[#E8711F] px-4 py-2 text-sm font-bold text-white disabled:opacity-50"
                >
                  Kirim
                </button>
              </div>
            </>
          )}
        </div>
      )}

      <button
        type="button"
        onClick={() => setOpen((value) => !value)}
        className="flex h-14 w-14 items-center justify-center rounded-full bg-[#E8711F] text-2xl text-white shadow-lg transition hover:bg-[#cf641b]"
        aria-label="Buka chat"
      >
        {open ? "×" : "💬"}
      </button>
    </div>
  );
}
