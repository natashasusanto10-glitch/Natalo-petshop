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
    console.error(error);
  }, [error]);

  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
      <span className="text-6xl">😿</span>
      <h1 className="mt-4 text-2xl font-black text-gray-900">Terjadi Kesalahan</h1>
      <p className="mt-2 max-w-sm text-sm text-gray-500">
        Ada sesuatu yang tidak beres. Coba muat ulang halaman atau kembali ke beranda.
      </p>
      <div className="mt-6 flex flex-wrap justify-center gap-3">
        <button
          onClick={reset}
          className="rounded-full bg-orange-500 px-6 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
        >
          Coba Lagi
        </button>
        <Link
          href="/"
          className="rounded-full border border-gray-200 px-6 py-3 text-sm font-bold text-gray-700 transition hover:border-orange-300 hover:text-orange-500"
        >
          Kembali ke Beranda
        </Link>
      </div>
    </div>
  );
}
