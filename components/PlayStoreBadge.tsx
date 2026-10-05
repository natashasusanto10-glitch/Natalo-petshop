"use client";

import { useEffect, useState } from "react";
import { PLAY_STORE_URL } from "@/components/open-in-app";
import { isCapacitorNative } from "@/lib/native-platform";

export function PlayStoreBadge({ className = "" }: { className?: string }) {
  const [isNative, setIsNative] = useState(false);
  useEffect(() => { setIsNative(isCapacitorNative()); }, []);
  if (isNative) return null;
  return (
    <a href={PLAY_STORE_URL} target="_blank" rel="noopener noreferrer"
      aria-label="Download Natalo Petshop di Google Play"
      className={`inline-flex items-center gap-2.5 rounded-xl bg-zinc-950 px-5 py-2.5 text-white shadow-md transition hover:bg-zinc-800 active:scale-95 ${className}`}>
      <svg viewBox="0 0 24 26" className="h-7 w-7" aria-hidden="true">
        <path fill="#4285F4" d="M2 1 14 13 2 25Z" />
        <path fill="#34A853" d="M2 1 18 10 14 13Z" />
        <path fill="#FBBC04" d="m18 10 5 3-5 3-4-3Z" />
        <path fill="#EA4335" d="m2 25 16-9-4-3Z" />
      </svg>
      <span className="flex flex-col items-start leading-tight">
        <span className="text-[10px] font-medium uppercase tracking-wide opacity-90">Download di</span>
        <span className="text-base font-black leading-none">Google Play</span>
      </span>
    </a>
  );
}
