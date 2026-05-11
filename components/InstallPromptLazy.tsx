"use client";

import dynamic from "next/dynamic";

// Wrapper client supaya dynamic({ ssr: false }) tetap legal — call ke
// next/dynamic dengan ssr:false hanya boleh di dalam Client Component
// (Next.js 14+). Kita pakai InstallPromptLazy di app/layout.tsx (server).
export const InstallPromptLazy = dynamic(
  () => import("@/components/InstallPrompt").then((m) => m.InstallPrompt),
  { ssr: false },
);
