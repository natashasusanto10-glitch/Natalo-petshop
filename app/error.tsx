"use client";

import { useEffect } from "react";
import Link from "next/link";

export default function ErrorPage({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[RuntimeError]", error);
  }, [error]);

  return (
    <div className="flex min-h-[70vh] items-center justify-center bg-[#f9f9f7] px-6 py-16">
      <div className="w-full max-w-[420px] text-center">
        <div className="mb-3 text-5xl" aria-hidden="true">
          😿
        </div>
        <h1 className="mb-2 text-6xl font-medium leading-none text-[#D85A30]">
          Oops!
        </h1>
        <h2 className="mb-3 text-xl font-medium text-zinc-950">
          Ada yang tidak beres
        </h2>
        <p className="mb-6 text-sm leading-6 text-zinc-500">
          Terjadi kesalahan di halaman ini. Coba muat ulang halaman atau
          kembali ke beranda.
        </p>
        <div className="flex flex-wrap justify-center gap-3">
          <button
            onClick={() => reset()}
            className="rounded-lg border-0 bg-[#D85A30] px-6 py-3 text-sm font-medium text-white transition hover:bg-[#c64d27]"
            type="button"
          >
            Coba Lagi
          </button>
          <Link
            href="/"
            className="rounded-lg border border-zinc-200 bg-white px-6 py-3 text-sm text-zinc-700 transition hover:border-zinc-300 hover:bg-zinc-50"
          >
            Kembali ke Beranda
          </Link>
        </div>
        {error.digest && (
          <p className="mt-6 font-mono text-xs text-zinc-400">
            Error ID: {error.digest}
          </p>
        )}
      </div>
    </div>
  );
}
