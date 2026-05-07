"use client";

import { useState } from "react";

export function ReviewForm({ productId }: { productId: string }) {
  const [rating, setRating] = useState(0);
  const [hover, setHover] = useState(0);
  const [name, setName] = useState("");
  const [comment, setComment] = useState("");
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!rating || !name.trim() || !comment.trim()) return;
    setStatus("loading");

    const res = await fetch("/api/reviews", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ productId, name: name.trim(), rating, comment: comment.trim() }),
    });

    if (res.ok) {
      setStatus("success");
      setRating(0);
      setName("");
      setComment("");
    } else {
      setStatus("error");
    }
  }

  if (status === "success") {
    return (
      <div className="rounded-2xl bg-green-50 p-6 text-center">
        <span className="text-3xl">🎉</span>
        <p className="mt-2 font-semibold text-green-800">Ulasan berhasil dikirim!</p>
        <p className="mt-1 text-sm text-green-600">Ulasan kamu sedang direview oleh admin dan akan segera tampil.</p>
        <button
          onClick={() => setStatus("idle")}
          className="mt-4 text-sm font-semibold text-orange-500 hover:underline"
        >
          Tulis ulasan lain
        </button>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {/* Star rating */}
      <div>
        <p className="mb-2 text-sm font-semibold text-gray-700">Rating</p>
        <div className="flex gap-1">
          {[1, 2, 3, 4, 5].map((star) => (
            <button
              key={star}
              type="button"
              onClick={() => setRating(star)}
              onMouseEnter={() => setHover(star)}
              onMouseLeave={() => setHover(0)}
              className="text-2xl transition"
            >
              <span className={(hover || rating) >= star ? "text-orange-400" : "text-gray-200"}>★</span>
            </button>
          ))}
        </div>
      </div>

      <div>
        <label className="block text-sm font-semibold text-gray-700">Nama kamu</label>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          required
          maxLength={80}
          placeholder="Nama atau inisial"
          className="mt-1.5 w-full rounded-2xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-orange-400 focus:ring-2 focus:ring-orange-100"
        />
      </div>

      <div>
        <label className="block text-sm font-semibold text-gray-700">Ulasan</label>
        <textarea
          value={comment}
          onChange={(e) => setComment(e.target.value)}
          required
          maxLength={1000}
          rows={3}
          placeholder="Bagikan pengalamanmu menggunakan produk ini..."
          className="mt-1.5 w-full rounded-2xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-orange-400 focus:ring-2 focus:ring-orange-100"
        />
      </div>

      {status === "error" && (
        <p className="text-sm text-red-500">Gagal mengirim ulasan. Coba lagi.</p>
      )}

      <button
        type="submit"
        disabled={status === "loading" || !rating}
        className="w-full rounded-full bg-orange-500 py-3 text-sm font-bold text-white transition hover:bg-orange-600 disabled:opacity-50"
      >
        {status === "loading" ? "Mengirim..." : "Kirim Ulasan"}
      </button>
    </form>
  );
}
