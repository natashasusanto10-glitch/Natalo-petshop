"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type SyncFn = (desired: boolean, signal: AbortSignal) => Promise<void>;

/**
 * Non-blocking optimistic toggle dengan last-write-wins.
 *
 * UI flip instan setiap tap. Request server di-debounce (default 250ms)
 * supaya rapid-toggle (on→off→on dalam < 250ms) hanya 1 round-trip ke
 * server — bukan 3. Request sebelumnya di-abort kalau user tap lagi
 * sebelum response. Kalau request gagal, UI revert ke state sebelum tap
 * pertama (snapshot saat toggle pertama kali dipanggil).
 *
 * Pakai untuk DB-backed toggle (favorite, follow, subscribe). Localstorage
 * toggle nggak butuh ini — cukup setState biasa.
 */
export function useOptimisticToggle({
  initial,
  sync,
  debounceMs = 250,
}: {
  initial: boolean;
  sync: SyncFn;
  debounceMs?: number;
}) {
  const [value, setValue] = useState(initial);
  const desiredRef = useRef(initial);
  const baselineRef = useRef(initial);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const ctrlRef = useRef<AbortController | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
      ctrlRef.current?.abort();
    };
  }, []);

  const toggle = useCallback(() => {
    const prev = desiredRef.current;
    const next = !prev;

    // First toggle in a burst — capture baseline for potential revert.
    if (timerRef.current === null && ctrlRef.current === null) {
      baselineRef.current = prev;
    }

    desiredRef.current = next;
    setValue(next);

    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      timerRef.current = null;
      ctrlRef.current?.abort();
      const ctrl = new AbortController();
      ctrlRef.current = ctrl;
      const target = desiredRef.current;
      sync(target, ctrl.signal)
        .then(() => {
          if (ctrlRef.current === ctrl) ctrlRef.current = null;
        })
        .catch((err) => {
          if ((err as { name?: string })?.name === "AbortError") return;
          if (ctrlRef.current !== ctrl) return; // superseded
          ctrlRef.current = null;
          // Roll back to baseline (state before the burst started).
          desiredRef.current = baselineRef.current;
          setValue(baselineRef.current);
        });
    }, debounceMs);
  }, [sync, debounceMs]);

  return { value, toggle };
}
