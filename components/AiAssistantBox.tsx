"use client";

import { useState } from "react";

export function AiAssistantBox() {
  const [question, setQuestion] = useState("");
  const [answer, setAnswer] = useState("");
  const [loading, setLoading] = useState(false);

  async function ask() {
    if (!question.trim()) return;
    setLoading(true);
    setAnswer("");

    const res = await fetch("/api/ai/product-assistant", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question }),
    });

    const data = await res.json();
    setAnswer(data.answer || "Belum ada jawaban.");
    setLoading(false);
  }

  return (
    <div className="rounded-3xl border border-zinc-200 bg-white p-5 shadow-sm">
      <p className="font-semibold text-zinc-950">AI Product Assistant</p>
      <p className="mt-1 text-sm text-zinc-600">Tanya rekomendasi produk, cara pakai, atau bundle yang cocok.</p>
      <textarea
        value={question}
        onChange={(e) => setQuestion(e.target.value)}
        placeholder="Contoh: Produk mana yang cocok untuk pemula?"
        className="mt-4 min-h-24 w-full rounded-2xl border border-zinc-200 p-3 text-sm outline-none focus:border-zinc-900"
      />
      <button onClick={ask} disabled={loading} className="mt-3 rounded-full bg-zinc-950 px-5 py-3 text-sm font-bold text-white disabled:opacity-50">
        {loading ? "Memproses..." : "Tanya AI"}
      </button>
      {answer ? <div className="mt-4 rounded-2xl bg-zinc-50 p-4 text-sm leading-6 text-zinc-700">{answer}</div> : null}
    </div>
  );
}
