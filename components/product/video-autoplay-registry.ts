"use client";
/**
 * Batasi jumlah video grid yang autoplay bersamaan supaya decoder browser
 * / HP tidak kehabisan (banyak <video> main sekaligus = janky/crash).
 * Sederhana: Set global berisi id yang sedang main, maks MAX_CONCURRENT.
 */
const MAX_CONCURRENT = 4;
const playing = new Set<string>();

export function requestPlay(id: string): boolean {
  if (playing.has(id)) return true;
  if (playing.size >= MAX_CONCURRENT) return false;
  playing.add(id);
  return true;
}

export function releasePlay(id: string): void {
  playing.delete(id);
}
