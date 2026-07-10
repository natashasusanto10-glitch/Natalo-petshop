"use client";

import { useEffect } from "react";
import { Button } from "@/components/admin/ui";

/**
 * Error boundary kanonik untuk route group admin (protected).
 * WAJIB client component (kontrak Next.js App Router error.tsx). Menangkap error
 * saat render segmen di bawahnya dan menawarkan pemulihan lewat reset().
 */
export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Log ke konsol agar mudah ditelusuri saat pengembangan.
    console.error(error);
  }, [error]);

  return (
    <div className="mx-auto max-w-lg px-4 py-16 text-center">
      <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-full bg-red-50 text-2xl">
        ⚠️
      </div>

      <h1 className="text-lg font-bold text-zinc-900">
        Terjadi kesalahan memuat halaman.
      </h1>
      <p className="mt-2 text-sm text-zinc-500">
        Coba muat ulang halaman ini. Jika masih bermasalah, hubungi pengembang.
      </p>

      {error.digest ? (
        <p className="mt-3 font-mono text-xs text-zinc-400">
          Kode: {error.digest}
        </p>
      ) : null}

      <div className="mt-6 flex justify-center">
        <Button variant="primary" onClick={() => reset()}>
          Coba lagi
        </Button>
      </div>
    </div>
  );
}
