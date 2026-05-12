"use client";

import { useState } from "react";

interface Props {
  productId: string;
  initialFavorited?: boolean;
  size?: "sm" | "md";
}

export function FavoriteButton({ productId, initialFavorited = false, size = "md" }: Props) {
  const [favorited, setFavorited] = useState(initialFavorited);
  const [loading, setLoading] = useState(false);

  async function toggle(e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    if (loading) return;

    setLoading(true);
    const next = !favorited;
    setFavorited(next); // optimistic update

    try {
      if (next) {
        await fetch("/api/member/favorites", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ productId }),
        });
      } else {
        await fetch(`/api/member/favorites/${productId}`, { method: "DELETE" });
      }
    } catch {
      setFavorited(!next); // revert on error
    } finally {
      setLoading(false);
    }
  }

  const iconSize = size === "sm" ? "h-4 w-4" : "h-5 w-5";
  const btnSize = size === "sm" ? "p-1.5" : "p-2";

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={loading}
      aria-label={favorited ? "Hapus dari favorit" : "Simpan ke favorit"}
      className={`${btnSize} rounded-full transition ${
        favorited
          ? "bg-red-50 text-red-500 hover:bg-red-100"
          : "bg-white/80 text-gray-400 hover:bg-white hover:text-red-400"
      } ${loading ? "opacity-50" : ""}`}
    >
      <svg
        className={iconSize}
        viewBox="0 0 24 24"
        fill={favorited ? "currentColor" : "none"}
        stroke="currentColor"
        strokeWidth={1.8}
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12Z"
        />
      </svg>
    </button>
  );
}
