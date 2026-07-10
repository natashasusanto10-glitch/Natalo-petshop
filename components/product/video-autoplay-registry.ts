"use client";
/**
 * Batasi jumlah video grid yang autoplay bersamaan supaya decoder browser
 * / HP tidak kehabisan (banyak <video> main sekaligus = janky/crash).
 * Sederhana: Set global berisi id yang sedang main, maks MAX_CONCURRENT.
 */
const MAX_CONCURRENT = 4;
const playing = new Set<string>();
const waiters = new Set<() => void>();

export function requestPlay(id: string): boolean {
  if (playing.has(id)) return true;
  if (playing.size >= MAX_CONCURRENT) return false;
  playing.add(id);
  return true;
}

export function releasePlay(id: string): void {
  if (!playing.delete(id)) return;
  // Beri tahu kartu yang menunggu slot supaya mencoba main lagi (cegah kartu
  // ke-5+ yang terlihat saat load nyangkut di foto walau slot sudah kosong).
  for (const cb of [...waiters]) cb();
}

/** Dipanggil saat sebuah slot play terbebas. Return fungsi unsubscribe. */
export function subscribeSlotFree(cb: () => void): () => void {
  waiters.add(cb);
  return () => waiters.delete(cb);
}
