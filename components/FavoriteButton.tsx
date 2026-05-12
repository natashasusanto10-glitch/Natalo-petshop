"use client";

import { useOptimisticToggle } from "@/lib/hooks/useOptimisticToggle";
import { hapticTap } from "@/lib/native/haptics";

interface Props {
  productId: string;
  initialFavorited?: boolean;
  size?: "sm" | "md";
}

export function FavoriteButton({ productId, initialFavorited = false, size = "md" }: Props) {
  const { value: favorited, toggle } = useOptimisticToggle({
    initial: initialFavorited,
    sync: async (desired, signal) => {
      const res = desired
        ? await fetch("/api/member/favorites", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ productId }),
            signal,
          })
        : await fetch(`/api/member/favorites/${productId}`, {
            method: "DELETE",
            signal,
          });
      if (!res.ok) throw new Error("Favorite sync failed");
    },
  });

  const iconSize = size === "sm" ? "h-4 w-4" : "h-5 w-5";
  const btnSize = size === "sm" ? "p-1.5" : "p-2";

  function handleClick(e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    hapticTap();
    toggle();
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      aria-label={favorited ? "Hapus dari favorit" : "Simpan ke favorit"}
      aria-pressed={favorited}
      className={`${btnSize} rounded-full transition-all duration-150 active:scale-90 ${
        favorited
          ? "bg-red-50 text-red-500 hover:bg-red-100"
          : "bg-white/80 text-gray-400 hover:bg-white hover:text-red-400"
      }`}
    >
      <svg
        className={`${iconSize} transition-transform duration-200 ${favorited ? "scale-110" : "scale-100"}`}
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
