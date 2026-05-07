"use client";

import { useEffect, useRef, useState } from "react";

type Thread = {
  id: string;
  updatedAt: string;
  unreadCount: number;
  user: { name: string; phone: string | null; email: string | null };
  lastMessage: { content: string; senderRole: string; createdAt: string } | null;
};

type Message = {
  id: string;
  senderRole: "ADMIN" | "CUSTOMER";
  content: string;
  createdAt: string;
};

export function AdminChatClient() {
  const [threads, setThreads] = useState<Thread[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  async function loadThreads() {
    const res = await fetch("/api/admin/chat", { cache: "no-store" });
    const data = await res.json();
    if (res.ok) {
      setThreads(data.threads || []);
      setActiveId((current) => current ?? data.threads?.[0]?.id ?? null);
    }
    setLoading(false);
  }

  async function loadMessages(threadId = activeId) {
    if (!threadId) return;
    const res = await fetch(`/api/admin/chat/${threadId}`, { cache: "no-store" });
    const data = await res.json();
    if (res.ok) setMessages(data.messages || []);
  }

  useEffect(() => {
    loadThreads();
    const t = setInterval(loadThreads, 4000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    if (!activeId) return;
    loadMessages(activeId);
    const t = setInterval(() => loadMessages(activeId), 2500);
    return () => clearInterval(t);
  }, [activeId]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  async function send() {
    if (!activeId || !draft.trim() || sending) return;
    setSending(true);
    const res = await fetch(`/api/admin/chat/${activeId}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: draft.trim() }),
    });
    if (res.ok) {
      setDraft("");
      await Promise.all([loadMessages(activeId), loadThreads()]);
    }
    setSending(false);
  }

  const activeThread = threads.find((thread) => thread.id === activeId) ?? null;

  return (
    <div className="grid min-h-[70vh] overflow-hidden rounded-2xl border border-zinc-200 bg-white lg:grid-cols-[320px_1fr]">
      <aside className="border-b border-zinc-200 lg:border-b-0 lg:border-r">
        <div className="border-b border-zinc-100 p-4">
          <h2 className="font-black text-zinc-950">Percakapan</h2>
          <p className="mt-1 text-xs text-zinc-500">Auto-refresh setiap beberapa detik</p>
        </div>
        <div className="max-h-[70vh] overflow-y-auto">
          {loading ? (
            <p className="p-4 text-sm text-zinc-500">Memuat chat...</p>
          ) : threads.length === 0 ? (
            <p className="p-4 text-sm text-zinc-500">Belum ada chat dari member.</p>
          ) : (
            threads.map((thread) => (
              <button
                key={thread.id}
                type="button"
                onClick={() => setActiveId(thread.id)}
                className={`block w-full border-b border-zinc-100 p-4 text-left transition hover:bg-zinc-50 ${
                  activeId === thread.id ? "bg-orange-50" : "bg-white"
                }`}
              >
                <div className="flex items-start justify-between gap-2">
                  <p className="font-bold text-zinc-950">{thread.user.name}</p>
                  {thread.unreadCount > 0 && (
                    <span className="rounded-full bg-[#E8711F] px-2 py-0.5 text-xs font-black text-white">
                      {thread.unreadCount}
                    </span>
                  )}
                </div>
                <p className="mt-1 line-clamp-1 text-xs text-zinc-500">
                  {thread.lastMessage?.content ?? "Belum ada pesan"}
                </p>
                <p className="mt-1 text-[11px] text-zinc-400">
                  {thread.user.phone || thread.user.email || "Member"}
                </p>
              </button>
            ))
          )}
        </div>
      </aside>

      <section className="flex min-h-[70vh] flex-col">
        {activeThread ? (
          <>
            <div className="border-b border-zinc-100 p-4">
              <h2 className="font-black text-zinc-950">{activeThread.user.name}</h2>
              <p className="mt-1 text-xs text-zinc-500">
                {activeThread.user.phone || activeThread.user.email || "Member"}
              </p>
            </div>
            <div className="flex-1 space-y-2 overflow-y-auto bg-zinc-50 p-4">
              {messages.map((message) => {
                const own = message.senderRole === "ADMIN";
                return (
                  <div key={message.id} className={`flex ${own ? "justify-end" : "justify-start"}`}>
                    <div
                      className={`max-w-[75%] rounded-2xl px-4 py-2 text-sm ${
                        own ? "bg-[#E8711F] text-white" : "bg-white text-zinc-800"
                      }`}
                    >
                      {message.content}
                    </div>
                  </div>
                );
              })}
              <div ref={bottomRef} />
            </div>
            <div className="flex gap-2 border-t border-zinc-100 p-4">
              <input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") send();
                }}
                placeholder="Balas pesan..."
                className="min-w-0 flex-1 rounded-full border border-zinc-300 px-4 py-2 text-sm outline-none focus:border-[#E8711F]"
              />
              <button
                type="button"
                disabled={sending || !draft.trim()}
                onClick={send}
                className="rounded-full bg-zinc-950 px-5 py-2 text-sm font-bold text-white disabled:opacity-50"
              >
                Kirim
              </button>
            </div>
          </>
        ) : (
          <div className="flex flex-1 items-center justify-center p-8 text-center text-sm text-zinc-500">
            Pilih percakapan member.
          </div>
        )}
      </section>
    </div>
  );
}
