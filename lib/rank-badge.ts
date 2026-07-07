// Warna pill peringkat "Terlaris". 1 emas, 2 perak, 3 perunggu-biru, 4+ netral.
export function rankBadgeClass(rank: number): string {
  if (rank === 1) return "bg-amber-400 text-white";
  if (rank === 2) return "bg-zinc-300 text-zinc-700";
  if (rank === 3) return "bg-blue-300 text-white";
  return "bg-white/95 text-zinc-700";
}
