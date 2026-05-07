"use client";

import { useEffect, useState } from "react";

function diffParts(target: number) {
  const diff = Math.max(0, target - Date.now());
  const totalSec = Math.floor(diff / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  return {
    h: String(h).padStart(2, "0"),
    m: String(m).padStart(2, "0"),
    s: String(s).padStart(2, "0"),
  };
}

export function FlashSaleCountdown({ endsAt }: { endsAt: number }) {
  const [parts, setParts] = useState({ h: "00", m: "00", s: "00" });

  useEffect(() => {
    setParts(diffParts(endsAt));
    const id = setInterval(() => setParts(diffParts(endsAt)), 1000);
    return () => clearInterval(id);
  }, [endsAt]);

  return (
    <div className="flex items-center gap-1 text-xs font-black text-white">
      <span className="rounded bg-zinc-900 px-1.5 py-0.5 tabular-nums">{parts.h}</span>
      <span className="text-zinc-900">:</span>
      <span className="rounded bg-zinc-900 px-1.5 py-0.5 tabular-nums">{parts.m}</span>
      <span className="text-zinc-900">:</span>
      <span className="rounded bg-zinc-900 px-1.5 py-0.5 tabular-nums">{parts.s}</span>
    </div>
  );
}
